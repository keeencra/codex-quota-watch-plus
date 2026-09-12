import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dashboard = TaskDashboardModel()
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
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("任务总览").font(.title2.bold())
                            Spacer()
                            Text(snapshot.codex.planLabel).font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        Text("手机掌握任务进展，随时处理关键确认。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    // Each link must be a separate Form row; links in one VStack share row activation.
                    NavigationLink {
                        TaskListView(model: dashboard, base: macURL, token: tokenInput)
                    } label: {
                        OverviewCard(title: "运行中",
                                     value: dashboard.taskError == nil ? dashboard.snapshot.map { String($0.runningCount) } ?? "—" : "—",
                                     subtitle: dashboard.taskError != nil ? "连接失败" : dashboard.snapshot.map { $0.attentionCount > 0 ? "\($0.attentionCount) 项需关注" : "查看任务阶段" } ?? "正在连接 Mac",
                                     symbol: "bolt.fill", tint: .cyan)
                    }.buttonStyle(.plain)
                    NavigationLink {
                        ApprovalInboxView(base: macURL, token: tokenInput)
                    } label: {
                        OverviewCard(title: "待审批", value: dashboard.approvalCount.map(String.init) ?? "—",
                                     subtitle: dashboard.approvalMessage, symbol: "checkmark.shield.fill", tint: .orange)
                    }.buttonStyle(.plain)
                    NavigationLink {
                        List {
                            Section("官方额度") { bucketRows(snapshot.codex.buckets) }
                            Section("今日用量") { row("Tokens", NumberFormatters.compactTokens(snapshot.codex.todayTokens)) }
                            Text(TaskTime.label(snapshot.updatedAt)).font(.caption).foregroundStyle(.secondary)
                        }.navigationTitle("剩余额度")
                    } label: {
                        let summary = WidgetQuotaSummary(snapshot: snapshot)
                        OverviewCard(title: "剩余额度", value: summary.windows.first?.percentLabel ?? "—",
                                     subtitle: summary.windows.map { $0.title + " " + $0.percentLabel }.joined(separator: " · "),
                                     symbol: "chart.pie.fill", tint: .green)
                    }.buttonStyle(.plain)
                    Text(errorText == nil ? "额度更新 · " + TaskTime.label(snapshot.updatedAt) : "额度同步失败，显示上次数据")
                        .font(.caption2).foregroundStyle(errorText == nil ? Color.secondary : Color.orange)
                }
                .listRowSeparator(.hidden)
                Section("账户余额") {
                    NavigationLink {
                        DeepSeekBalanceView(balance: snapshot.deepseek)
                    } label: {
                        DeepSeekBalanceCard(balance: snapshot.deepseek)
                    }.buttonStyle(.plain)
                }
                Section("连接与同步") {
                    DisclosureGroup("Mac 连接设置") {
                    TextField("Mac 服务地址", text: $macURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("WATCH_TOKEN", text: tokenBinding)
                    Button {
                        isShowingPairingScanner = true
                    } label: {
                        Label("扫描配对二维码", systemImage: "qrcode.viewfinder")
                    }
                    }
                    Button(isLoading ? "正在同步…" : "刷新并同步数据") {
                        Task { await fetch() }
                    }
                    .disabled(isLoading)
                    Toggle("自动刷新额度", isOn: $autoRefreshEnabled)
                    Text("手机可独立查看额度、任务与审批；已连接手表时会自动同步。任务与审批每 10 秒更新。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
                }

                Section("任务提醒") {
                    DisclosureGroup("通知设置与状态") {
                    if let config = snapshot.notifications, config.enabled {
                        Label(config.provider == "bark" ? "Bark 推送已启用" : "ntfy 推送已启用", systemImage: "bell.badge")
                        if config.provider != "bark" {
                        Text("在 ntfy 添加订阅：服务器使用 ntfy.sh，主题粘贴下方复制的内容。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("复制订阅主题") {
                            UIPasteboard.general.string = config.topic
                        }
                        Text(config.topic).font(.caption.monospaced()).textSelection(.enabled)
                        Text("允许 ntfy 通知即可在手机接收提醒；如有手表，可在 Watch App → 通知中开启 ntfy 镜像。")
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
                    Text("从 Bark 首页复制 api.day.app 的推送地址，粘贴后保存。允许 Bark 通知即可在手机接收提醒；如有手表，可在 Watch App → 通知中开启 Bark 镜像。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("安装 Bark－给你的手机发推送", destination: URL(string: "https://apps.apple.com/app/id1403753865")!)
                    Text("推送只包含状态，不发送原始任务、命令和文件路径。")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("更多") {
                    NavigationLink {
                        List {
                            Section {
                                HStack(spacing: 14) {
                                    Image("BrandIcon").resizable().frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 15))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("码伴 · CodeCompanion").font(.headline)
                                        Text("随身的 AI 开发助手").foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 8)
                            }
                            Section("手机即可使用") {
                                Label("按项目查看任务与进展", systemImage: "folder")
                                Label("查看并处理远程审批", systemImage: "checkmark.shield")
                                Label("Codex 额度与可选 DeepSeek 余额", systemImage: "chart.pie")
                                Label("桌面小组件与任务提醒", systemImage: "bell")
                            }
                            Section("Apple Watch 可选") {
                                Text("没有手表也能使用上述手机功能。有手表时，可增加抬腕查看、通知镜像和快速审批。")
                            }
                            Section("连接要求") {
                                Text("需要运行本项目服务的 Mac 在线提供数据。配置 HTTPS 后可外出访问；任务提醒需要配置 Bark 或 ntfy。")
                            }
                            Section("项目与致谢") {
                                Text("由 keeencra 持续维护，原名 Codex Quota Watch Plus。保留所用开源代码的许可证、版权和上游致谢。")
                                Link("项目源码与许可证", destination: URL(string: "https://github.com/keeencra/codex-quota-watch-plus")!)
                            }
                        }.navigationTitle("关于码伴")
                    } label: {
                        Label("关于码伴", systemImage: "info.circle")
                    }
                    DisclosureGroup("连接诊断") {
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
                }

                if let errorText {
                    Section("Error") {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("码伴")
            .toolbar {
                Button("刷新") { Task {
                    async let tasks: () = dashboard.refresh(base: macURL, token: tokenInput)
                    await fetch()
                    await tasks
                } }
            }
            .task(id: macURL + tokenInput + String(describing: scenePhase)) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await dashboard.refresh(base: macURL, token: tokenInput)
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                }
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
            barkStatus = "Bark 配置已保存。手机可直接接收提醒；测试手表镜像时请锁定手机并佩戴手表。"
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
