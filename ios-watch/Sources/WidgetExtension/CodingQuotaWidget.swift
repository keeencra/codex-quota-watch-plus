import SwiftUI
import WidgetKit

struct CodingQuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct CodingQuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodingQuotaWidgetEntry {
        CodingQuotaWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodingQuotaWidgetEntry) -> Void) {
        completion(CodingQuotaWidgetEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodingQuotaWidgetEntry>) -> Void) {
        let now = Date()
        let refreshAfter = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [CodingQuotaWidgetEntry(date: now, snapshot: loadSnapshot())], policy: .after(refreshAfter)))
    }

    private func loadSnapshot() -> WatchSnapshot? {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        guard let json = defaults?.string(forKey: AppConstants.snapshotKey),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}

struct CodingQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodingQuotaWidgetEntry

    var body: some View {
        let summary = WidgetQuotaSummary(snapshot: entry.snapshot)
        ZStack {
            Color.black
            switch family {
            case .systemMedium:
                medium(summary)
            default:
                small(summary)
            }
        }
        .containerBackground(Color.black, for: .widget)
    }

    private func small(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(summary, showsMeta: false)
            smallQuotaRow(summary.fiveHour, accent: .codexWidgetGreen, track: .codexWidgetGreenTrack)
            smallQuotaRow(
                summary.sevenDay ?? WidgetQuotaWindow(title: "7 天", bucket: nil, fallback: .placeholder(status: "not_configured")),
                accent: .codexWidgetBlue,
                track: .codexWidgetBlueTrack
            )
            Spacer(minLength: 0)
            Text(shortUpdateLabel(summary.updatedLabel))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
                .lineLimit(1)
        }
        .padding(15)
    }

    private func medium(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            header(summary, showsMeta: true)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    mediumQuotaRow(summary.fiveHour, accent: .codexWidgetGreen, track: .codexWidgetGreenTrack)
                    mediumQuotaRow(
                        summary.sevenDay ?? WidgetQuotaWindow(title: "7 天", bucket: nil, fallback: .placeholder(status: "not_configured")),
                        accent: .codexWidgetBlue,
                        track: .codexWidgetBlueTrack
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                todayPanel(summary)
            }
        }
        .padding(16)
    }

    private func header(_ summary: WidgetQuotaSummary, showsMeta: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Codex")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if showsMeta {
                Text("\(summary.modelLabel) · \(shortUpdateLabel(summary.updatedLabel))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.codexWidgetSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            } else {
                Circle()
                    .fill(statusColor(summary.status))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func smallQuotaRow(_ window: WidgetQuotaWindow, accent: Color, track: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(widgetTitle(window.title))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.codexWidgetSecondary)
                Spacer(minLength: 6)
                Text(window.percentLabel)
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundStyle(color(for: window.tone, identity: accent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            segmentedProgress(window, identity: accent, track: track, segmentCount: 12, height: 8, spacing: 3)
            Text(window.refillLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func mediumQuotaRow(_ window: WidgetQuotaWindow, accent: Color, track: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(widgetTitle(window.title))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.codexWidgetSecondary)
                Spacer(minLength: 4)
                Text(window.percentLabel)
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundStyle(color(for: window.tone, identity: accent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            segmentedProgress(window, identity: accent, track: track, segmentCount: 14, height: 8, spacing: 3)
            Text(window.refillLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func todayPanel(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("今日 token")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
            Text(summary.todayLabel.replacingOccurrences(of: "今日 ", with: ""))
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            tokenBars(summary.tokenBins)
        }
        .frame(width: 104, alignment: .leading)
    }

    private func tokenBars(_ bins: [TwoHourTokenBin]) -> some View {
        let visibleBins = Array(bins.suffix(8))
        let maxTokens = max(visibleBins.map(\.tokens).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(visibleBins) { bin in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.codexWidgetGreen.opacity(bin.tokens == 0 ? 0.32 : 0.88))
                    .frame(width: 8, height: max(5, 36 * bin.intensity(maxTokens: maxTokens)))
            }
        }
        .frame(height: 38, alignment: .bottom)
    }

    private func segmentedProgress(
        _ window: WidgetQuotaWindow,
        identity: Color,
        track: Color,
        segmentCount: Int,
        height: CGFloat,
        spacing: CGFloat
    ) -> some View {
        let filled = Int((window.progress * Double(segmentCount)).rounded(.down))
        let activeSegments = window.progress > 0 ? max(1, filled) : 0
        let fill = color(for: window.tone, identity: identity)
        return HStack(spacing: spacing) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < activeSegments ? fill : track)
            }
        }
        .frame(height: height)
    }

    private func widgetTitle(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "")
    }

    private func shortUpdateLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "刷新 ", with: "")
    }

    private func statusColor(_ status: WidgetQuotaSummary.Status) -> Color {
        switch status {
        case .ready:
            return .codexWidgetGreen
        case .setup:
            return .codexWidgetAmber
        case .error:
            return .codexWidgetRed
        }
    }

    private func color(for tone: WidgetQuotaTone, identity: Color) -> Color {
        switch tone {
        case .normal:
            return identity
        case .warning:
            return .codexWidgetAmber
        case .critical:
            return .codexWidgetRed
        case .unavailable:
            return .codexWidgetSecondary
        }
    }

}

private extension Color {
    static let codexWidgetGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let codexWidgetBlue = Color(red: 0.23, green: 0.62, blue: 1.0)
    static let codexWidgetAmber = Color(red: 1.0, green: 0.70, blue: 0.04)
    static let codexWidgetRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let codexWidgetSecondary = Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.58)
    static let codexWidgetGreenTrack = Color(red: 0.09, green: 0.14, blue: 0.10)
    static let codexWidgetBlueTrack = Color(red: 0.09, green: 0.14, blue: 0.23)
}

struct CodingQuotaWidget: Widget {
    let kind = "CodingQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodingQuotaWidgetProvider()) { entry in
            CodingQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Quota")
        .description("Shows the latest Codex quota snapshot synced by the iPhone app.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct CodingQuotaWidgetMain: WidgetBundle {
    var body: some Widget {
        CodingQuotaWidget()
    }
}
