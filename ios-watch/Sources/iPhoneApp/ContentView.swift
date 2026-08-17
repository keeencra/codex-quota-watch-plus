import SwiftUI

struct ContentView: View {
    @AppStorage(AppConstants.macURLKey, store: UserDefaults(suiteName: AppConstants.appGroupID))
    private var macURL: String = "http://127.0.0.1:8787"

    @AppStorage(AppConstants.autoRefreshKey, store: UserDefaults(suiteName: AppConstants.appGroupID))
    private var autoRefreshEnabled: Bool = true

    @State private var snapshot: WatchSnapshot = SharedUsageStore.shared.load()
    @State private var isLoading = false
    @State private var statusText = "Ready"
    @State private var errorText: String?
    @State private var tokenInput = ""
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var isShowingPairingScanner = false
    @State private var watchConnectivityStatus = "unknown"

    private let autoRefreshIntervalSeconds: UInt64 = 300

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac Agent") {
                    TextField("http://Mac-IP:8787", text: $macURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("WATCH_TOKEN", text: tokenBinding)
                    Button {
                        isShowingPairingScanner = true
                    } label: {
                        Label("Scan Pairing QR", systemImage: "qrcode.viewfinder")
                    }
                    Button(isLoading ? "Fetching..." : "Fetch & Sync to Watch") {
                        Task { await fetch() }
                    }
                    .disabled(isLoading)
                    Toggle("Auto refresh while open", isOn: $autoRefreshEnabled)
                    Text("Refreshes while open, schedules background refresh, and responds when Watch opens.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
                }

                Section("Diagnostics") {
                    row("Mac URL", DiagnosticsText.macURLStatus(macURL))
                    row("Token", DiagnosticsText.tokenStatus(tokenInput))
                    row("Last sync", NumberFormatters.compactDate(snapshot.updatedAt))
                    row("Auto refresh", autoRefreshEnabled ? "on" : "off")
                    row("Watch", watchConnectivityStatus)
                    row("Last fetch", diagnosticFetchStatus)
                    Button {
                        refreshDiagnostics()
                    } label: {
                        Label("Refresh Diagnostics", systemImage: "stethoscope")
                    }
                }

                Section("Codex") {
                    row("Status", snapshot.codex.status)
                    row("Window", snapshot.codex.window ?? "--")
                    row("Today", NumberFormatters.compactTokens(snapshot.codex.todayTokens))
                    bucketRows(snapshot.codex.buckets)
                }

                if let errorText {
                    Section("Error") {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Codex Quota")
            .toolbar {
                Button("Sync") { Task { await fetch() } }
            }
            .onAppear {
                _ = PhoneConnectivity.shared
                loadToken()
                refreshDiagnostics()
                startAutoRefreshIfNeeded()
                BackgroundRefreshService.scheduleIfEnabled()
            }
            .onDisappear {
                stopAutoRefresh()
            }
            .onChange(of: autoRefreshEnabled) { _, _ in
                startAutoRefreshIfNeeded()
                if autoRefreshEnabled {
                    BackgroundRefreshService.scheduleIfEnabled()
                } else {
                    BackgroundRefreshService.cancel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PhoneConnectivity.refreshRequestNotification)) { notification in
                applyWatchRefreshResult(notification.object)
            }
            .sheet(isPresented: $isShowingPairingScanner) {
                PairingScannerSheet(
                    onPairing: apply(pairing:),
                    onError: { message in
                        errorText = message
                        statusText = message
                    }
                )
            }
        }
    }

    private func applyWatchRefreshResult(_ object: Any?) {
        refreshDiagnostics()
        guard let result = object as? BackgroundRefreshResult else {
            snapshot = SharedUsageStore.shared.load()
            statusText = "Watch requested refresh"
            return
        }

        switch result {
        case .success(let updatedSnapshot):
            snapshot = updatedSnapshot
            errorText = nil
            statusText = "Synced \(NumberFormatters.compactDate(updatedSnapshot.updatedAt))"
        case .failure(let message):
            snapshot = SharedUsageStore.shared.load()
            errorText = message
            statusText = message
        }
    }

    private var tokenBinding: Binding<String> {
        Binding(
            get: { tokenInput },
            set: { newValue in
                tokenInput = newValue
                if newValue.isEmpty {
                    WatchTokenStore.delete()
                } else if let token = WatchToken.sanitize(newValue) {
                    tokenInput = token
                    _ = WatchTokenStore.save(token)
                }
            }
        )
    }

    private var diagnosticFetchStatus: String {
        if isLoading { return "loading" }
        if errorText != nil { return "error" }
        return statusText
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func bucketRows(_ buckets: [QuotaBucket]?) -> some View {
        if let buckets, !buckets.isEmpty {
            ForEach(Array(buckets.prefix(4).enumerated()), id: \.offset) { _, bucket in
                HStack {
                    Text(bucket.label ?? bucket.window ?? "bucket")
                    Spacer()
                    Text("\(NumberFormatters.percent(bucket.remainingPercent)) · \(bucket.resetIn ?? "--")")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
    }

    @MainActor
    private func fetch(reason: String? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        statusText = reason ?? "Requesting \(macURL)/watch..."
        errorText = nil
        do {
            let result = try await BackgroundRefreshService.fetchAndSync(macURL: macURL, token: tokenInput)
            snapshot = result
            BackgroundRefreshService.scheduleIfEnabled()
            refreshDiagnostics()
            statusText = "Synced \(NumberFormatters.compactDate(result.updatedAt))"
        } catch {
            errorText = error.localizedDescription
            refreshDiagnostics()
            statusText = error.localizedDescription
        }
        isLoading = false
    }

    private func startAutoRefreshIfNeeded() {
        stopAutoRefresh()
        guard autoRefreshEnabled else {
            statusText = "Auto refresh off"
            return
        }
        autoRefreshTask = Task {
            await fetch(reason: "Auto refreshing...")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: autoRefreshIntervalSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                await fetch(reason: "Auto refreshing...")
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func refreshDiagnostics() {
        watchConnectivityStatus = PhoneConnectivity.shared.diagnosticsStatus
    }

    private func loadToken() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        tokenInput = WatchTokenStore.migrateLegacyTokenIfNeeded(defaults: defaults)
    }

    @MainActor
    private func apply(pairing: PairingPayload) {
        macURL = pairing.macURL
        tokenInput = pairing.token
        _ = WatchTokenStore.save(pairing.token)
        statusText = "Paired \(pairing.macURL)"
        errorText = nil
        Task { await fetch(reason: "Paired. Fetching...") }
    }
}
