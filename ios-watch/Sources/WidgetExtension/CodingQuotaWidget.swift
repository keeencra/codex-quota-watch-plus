import SwiftUI
import WidgetKit
import AppIntents

struct CodingQuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
    var refreshFailed = false
    var usageTitle = "今日 token"
    var usageValue: String? = nil
    var showsTokenHistory = true
}

struct CodingQuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodingQuotaWidgetEntry {
        CodingQuotaWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodingQuotaWidgetEntry) -> Void) {
        completion(CodingQuotaWidgetEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodingQuotaWidgetEntry>) -> Void) {
        Task {
            let result = await WidgetSnapshotFetcher.refresh {
                let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
                defaults.synchronize()
                let macURL = defaults.string(forKey: AppConstants.macURLKey) ?? ""
                return try await UsageClient().fetchCompact(
                    macAgentBaseURL: macURL,
                    token: WatchTokenStore.load(),
                    timeoutSeconds: 10
                )
            }
            let now = Date()
            let entry = CodingQuotaWidgetEntry(date: now, snapshot: result.snapshot, refreshFailed: result.failed)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    private func loadSnapshot() -> WatchSnapshot? {
        SharedUsageStore.shared.loadOptional()
    }
}

struct RefreshQuotaWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新额度"
    static var description = IntentDescription("从 Mac 获取最新额度。")

    func perform() async throws -> some IntentResult {
        // WidgetKit reloads the timeline after an interaction; the provider fetches live data.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CodingQuotaWidget: Widget {
    let kind = "CodingQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodingQuotaWidgetProvider()) { entry in
            UnifiedWidgetContent(entry: entry)
        }
        .configurationDisplayName("码伴")
        .description("显示 Codex 额度与 DeepSeek 账户余额，可独立联网或点击刷新。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct CodingQuotaWidgetMain: WidgetBundle {
    var body: some Widget {
        CodingQuotaWidget()
    }
}

struct UnifiedWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodingQuotaWidgetEntry
    var body: some View {
        if family == .systemLarge {
            QuotaWidgetView(entry: .init(date: entry.date, snapshot: overviewSnapshot(entry)), compact: false, expanded: true)
                .padding(16)
                .containerBackground(Color.black, for: .widget)
                .environment(\.colorScheme, .dark)
        } else {
            CodingQuotaWidgetView(entry: entry)
        }
    }
}

private func overviewSnapshot(_ entry: CodingQuotaWidgetEntry) -> WidgetSnapshot {
    guard let source = entry.snapshot else { return .empty }
    let summary = WidgetQuotaSummary(snapshot: source)
    let iso = ISO8601DateFormatter()
    let updated = iso.date(from: source.updatedAt) ?? { iso.formatOptions.insert(.withFractionalSeconds); return iso.date(from: source.updatedAt) }() ?? .distantPast
    return WidgetSnapshot(updatedAt: updated, plan: summary.planLabel,
        windows: WatchDisplayData.codexWindows(from: source.codex.buckets).windows.compactMap { bucket in
            guard let remaining = bucket.remainingPercent else { return nil }
            return .init(label: bucket.window == "7d" ? "周" : (bucket.window ?? bucket.label ?? "额度"), remaining: Int(remaining), resetsAt: bucket.resetAt.flatMap { Date(timeIntervalSince1970: $0) })
        },
        balances: source.deepseek?.balanceInfos.map { .init(currency: $0.currency, amount: ($0.currency == "CNY" ? "¥" : ($0.currency == "USD" ? "$" : "")) + $0.compactTotal) } ?? [],
        codexError: entry.refreshFailed ? "刷新失败" : source.codex.error,
        balanceError: source.deepseek?.status == "not_configured" ? "未配置 API Key" : nil,
        resetCredits: source.resetCredits.map { .init(availableCount: $0.availableCount, expirations: $0.expirations.map { Date(timeIntervalSince1970: $0) }) })
}
