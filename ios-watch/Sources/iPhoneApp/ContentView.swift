import SwiftUI
import UIKit

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
    @State private var barkAddress = ""
    @State private var isSavingBark = false
    @State private var barkStatus: String?
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

                Section("任务提醒") {
                    if let config = snapshot.notifications, config.enabled {
                        Label(config.provider == "bark" ? "Bark 推送已启用" : "ntfy 推送已启用", systemImage: "bell.badge")
                        if config.provider != "bark" {
                        Text("在 ntfy 添加订阅：服务器使用 ntfy.sh，主题粘贴下方复制的内容。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("复制订阅主题") {
                            UIPasteboard.general.string = config.topic
                        }
                        Text(config.topic).font(.caption.monospaced()).textSelection(.enabled)
                        Text("允许 ntfy 通知，并在 Watch App → 通知中开启 ntfy 镜像。")
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let delivered = config.lastDeliveryAt {
                            row("最近提交到推送服务", NumberFormatters.compactDate(delivered))
                        }
                        if config.pendingCount > 0 {
                            row("等待发送", String(config.pendingCount))
                        }
                    } else {
                        Text("Mac 尚未配置推送，或需要先同步。")
                            .foregroundStyle(.secondary)
                    }
                    SecureField("粘贴 Bark 推送地址", text: $barkAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(isSavingBark ? "正在保存…" : "保存 Bark 配置") {
                        Task { await saveBark() }
                    }
                    .disabled(isSavingBark || barkAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let barkStatus {
                        Text(barkStatus).font(.footnote)
                    }
                    Text("从 Bark 首页复制 api.day.app 的推送地址，粘贴后保存。允许 Bark 通知，并在 Watch App → 通知中开启 Bark 镜像。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("安装 Bark－给你的手机发推送", destination: URL(string: "https://apps.apple.com/app/id1403753865")!)
                    Text("推送只包含状态，不发送原始任务、命令和文件路径。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("最近任务") {
                    if snapshot.taskEvents.isEmpty {
                        Text("暂无记录；启用任务事件后会显示在这里。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.taskEvents) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.project).lineLimit(1)
                                Spacer()
                                Text(event.statusLabel)
                                    .foregroundStyle(event.status == "needs_approval" ? Color.orange : Color.secondary)
                            }
                            Text(NumberFormatters.compactDate(event.updatedAt))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("显示最近同步的任务状态；提醒由已配置的通知 App 推送。")
                        .font(.caption).foregroundStyle(.secondary)
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
                    row("套餐", snapshot.codex.planLabel)
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

    @MainActor
    private func saveBark() async {
        isSavingBark = true
        barkStatus = nil
        defer { isSavingBark = false }
        do {
            try await UsageClient().configureBark(macAgentBaseURL: macURL, token: tokenInput, address: barkAddress)
            barkAddress = ""
            barkStatus = "Bark 配置已保存。测试时请锁定手机并佩戴手表。"
            await fetch()
        } catch {
            barkStatus = "保存失败，请检查 Bark 地址和 Mac 连接后重试。"
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
