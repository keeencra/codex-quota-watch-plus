import SwiftUI
import WidgetKit

struct QuotaComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
    var failed = false
}

struct QuotaComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaComplicationEntry {
        .init(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (QuotaComplicationEntry) -> Void) {
        completion(.init(date: Date(), snapshot: context.isPreview ? nil : SharedUsageStore.shared.loadOptional()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaComplicationEntry>) -> Void) {
        Task {
            let result = await WidgetSnapshotFetcher.refresh {
                guard let config = WatchAgentConfigStore().load() else { throw UsageClientError.emptyToken }
                return try await UsageClient().fetchCompact(macAgentBaseURL: config.macURL, token: config.token, timeoutSeconds: 10)
            }
            let now = Date()
            // A second entry marks cached data even when watchOS delays the next network refresh.
            let staleAt = now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [
                .init(date: now, snapshot: result.snapshot, failed: result.failed),
                .init(date: staleAt, snapshot: result.snapshot, failed: true)
            ], policy: .after(staleAt)))
        }
    }
}

struct QuotaComplicationView: View {
    let entry: QuotaComplicationEntry
    var body: some View {
        let data = WatchComplicationSummary(snapshot: entry.snapshot, failed: entry.failed, now: entry.date)
        VStack(alignment: .leading, spacing: data.showsDeepSeek ? 2 : 5) {
            Text(data.resetLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("剩余额度 \(data.percent)")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let progress = data.progress {
                Gauge(value: progress, in: 0...1) { Text("Codex 剩余额度") }
                    .gaugeStyle(.linearCapacity)
                    .labelsHidden()
                    .tint(progress <= 0.1 ? Color.red : Color.green)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity)
            } else {
                Text("额度暂不可用")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if data.showsDeepSeek || data.cached {
                HStack(spacing: 4) {
                    Text(data.balance)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if data.cached {
                        Text("缓存").font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.black, for: .widget)
        .accessibilityElement(children: .combine)
    }
}

@main
struct QuotaWatchWidget: Widget {
    let kind = "QuotaWatchComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaComplicationProvider()) { entry in
            QuotaComplicationView(entry: entry)
        }
        .configurationDisplayName("码伴 · 额度与余额")
        .description("Codex 剩余额度进度条与 DeepSeek 余额，适用于表盘中央矩形位置。")
        .supportedFamilies([.accessoryRectangular])
    }
}
