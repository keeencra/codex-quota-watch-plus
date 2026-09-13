import SwiftUI
import WidgetKit
import AppIntents

struct CodingQuotaWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WatchSnapshot?
    var refreshFailed = false
    var usageTitle = "近期任务 token"
    var usageValue: String? = nil
    var showsTokenHistory = false
}
struct RefreshQuotaWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新额度"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
struct MacClassicProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodingQuotaWidgetEntry { classicEntry(.preview) }
    func getSnapshot(in context: Context, completion: @escaping (CodingQuotaWidgetEntry) -> Void) {
        completion(classicEntry(context.isPreview ? .preview : WidgetSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CodingQuotaWidgetEntry>) -> Void) {
        let source = WidgetSnapshotStore.read()
        let current = classicEntry(source)
        var stale = current
        stale.date = max(Date().addingTimeInterval(60), source.updatedAt.addingTimeInterval(301))
        stale.refreshFailed = true
        completion(Timeline(entries: [current, stale], policy: .after(Date().addingTimeInterval(900))))
    }
    func classicEntry(_ source: WidgetSnapshot) -> CodingQuotaWidgetEntry {
        let iso = ISO8601DateFormatter()
        let buckets: [[String: Any]] = source.windows.enumerated().map { index, window in
            var bucket: [String: Any] = ["id": "codex:\(index)", "window": window.label == "周" ? "7d" : window.label,
                "remaining_percent": window.remaining, "status": "ok"]
            if let date = window.resetsAt { bucket["reset_in"] = "\(max(0, Int(date.timeIntervalSinceNow / 60)))m" }
            return bucket
        }
        let balances: [[String: String]] = source.balances.map { balance in
            ["currency": balance.currency, "total_balance": balance.amount.filter { "0123456789.-".contains($0) }, "granted_balance": "0", "topped_up_balance": "0"]
        }
        var object: [String: Any] = ["updated_at": iso.string(from: source.updatedAt),
            "codex": ["plan_type": source.plan.lowercased(), "status": source.codexError == nil ? "ok" : "error", "source": "mac-local", "today_tokens": 0, "buckets": buckets],
            "deepseek": ["status": source.balanceError == "未配置 API Key" ? "not_configured" : (balances.isEmpty ? "error" : "ok"), "balance_infos": balances]]
        if let credits = source.resetCredits {
            object["reset_credits"] = ["available_count": credits.availableCount,
                                      "expirations": credits.expirations.map { $0.timeIntervalSince1970 }]
        }
        let snapshot = (try? JSONSerialization.data(withJSONObject: object)).flatMap { try? JSONDecoder().decode(WatchSnapshot.self, from: $0) }
        return .init(date: Date(), snapshot: snapshot, refreshFailed: source.isStale(at: Date()) || source.codexError != nil,
                     usageValue: source.recentTokens.map { NumberFormatters.compactTokens($0) } ?? "—")
    }
}
