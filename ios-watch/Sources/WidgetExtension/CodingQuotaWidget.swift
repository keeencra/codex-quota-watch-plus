import SwiftUI
import WidgetKit
import AppIntents

struct CodingQuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
    var refreshFailed = false
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
        WidgetCenter.shared.reloadTimelines(ofKind: "CodingQuotaWidget")
        return .result()
    }
}

struct CodingQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodingQuotaWidgetEntry

    var body: some View {
        let summary = WidgetQuotaSummary(snapshot: entry.snapshot)
        ZStack {
            Color.black
            if entry.snapshot?.showsDeepSeekInWidget == true {
                switch family {
                case .systemMedium: medium(summary)
                default: smallWithDeepSeek(summary)
                }
            } else {
                switch family {
                case .systemMedium: codexOnlyMedium(summary)
                default: codexOnlySmall(summary)
                }
            }
        }
        .containerBackground(Color.black, for: .widget)
    }

    private func smallWithDeepSeek(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            header(summary, showsMeta: false)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(summary.windows.enumerated()), id: \.offset) { index, window in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(widgetTitle(window.title)).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.codexWidgetSecondary)
                            Spacer(minLength: 3)
                            Text(window.percentLabel).font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(color(for: window.tone, identity: index == 0 ? .codexWidgetGreen : .codexWidgetBlue))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        segmentedProgress(window,
                            identity: index == 0 ? .codexWidgetGreen : .codexWidgetBlue,
                            track: index == 0 ? .codexWidgetGreenTrack : .codexWidgetBlueTrack,
                            segmentCount: 12, height: summary.windows.count > 1 ? 4 : 6, spacing: 3)
                    }
                }
                if summary.windows.isEmpty { Text("暂无额度数据").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            deepSeekPanel
            Spacer(minLength: 0)
            Text(updateLabel(summary))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
                .lineLimit(1)
        }
        .padding(10)
    }

    private func codexOnlySmall(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: summary.windows.count > 1 ? 3 : 9) {
            codexOnlyHeader(summary, showsMeta: false)
            ForEach(Array(summary.windows.enumerated()), id: \.offset) { index, window in
                smallQuotaRow(window,
                    accent: index == 0 ? .codexWidgetGreen : .codexWidgetBlue,
                    track: index == 0 ? .codexWidgetGreenTrack : .codexWidgetBlueTrack,
                    compact: summary.windows.count > 1)
            }
            if summary.windows.isEmpty { Text("暂无额度数据").foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Text(updateLabel(summary))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
                .lineLimit(1)
        }
        .padding(10)
    }

    private func codexOnlyMedium(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            codexOnlyHeader(summary, showsMeta: true)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(summary.windows.enumerated()), id: \.offset) { index, window in
                        mediumQuotaRow(window,
                            accent: index == 0 ? .codexWidgetGreen : .codexWidgetBlue,
                            track: index == 0 ? .codexWidgetGreenTrack : .codexWidgetBlueTrack)
                    }
                    if summary.windows.isEmpty { Text("暂无额度数据").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                codexOnlyTodayPanel(summary)
            }
        }
        .padding(16)
    }

    private func codexOnlyHeader(_ summary: WidgetQuotaSummary, showsMeta: Bool) -> some View {
        HStack(spacing: showsMeta ? 8 : 4) {
            Text("Codex · \(summary.planLabel)")
                .font(.system(size: showsMeta ? 20 : 14, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if showsMeta {
                Text(updateLabel(summary))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.codexWidgetSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            } else {
                Circle()
                    .fill(statusColor(summary.status))
                    .frame(width: 8, height: 8)
            }
            Button(intent: RefreshQuotaWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: showsMeta ? 28 : 22, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新额度")
        }
    }

    private func codexOnlyTodayPanel(_ summary: WidgetQuotaSummary) -> some View {
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

    private func medium(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            header(summary, showsMeta: true)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(summary.windows.enumerated()), id: \.offset) { index, window in
                        mediumQuotaRow(window,
                            accent: index == 0 ? .codexWidgetGreen : .codexWidgetBlue,
                            track: index == 0 ? .codexWidgetGreenTrack : .codexWidgetBlueTrack)
                    }
                    if summary.windows.isEmpty { Text("暂无额度数据").foregroundStyle(.secondary) }
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
        HStack(spacing: showsMeta ? 8 : 4) {
            Text("Codex · \(summary.planLabel)")
                .font(.system(size: showsMeta ? 20 : 14, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if showsMeta {
                Text(updateLabel(summary))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.codexWidgetSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            Button(intent: RefreshQuotaWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: showsMeta ? 28 : 22, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新额度")
        }
    }

    private func updateLabel(_ summary: WidgetQuotaSummary) -> String {
        let time = shortUpdateLabel(summary.updatedLabel)
        return entry.refreshFailed ? "未更新 · \(time)" : time
    }

    private func smallQuotaRow(_ window: WidgetQuotaWindow, accent: Color, track: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(widgetTitle(window.title))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.codexWidgetSecondary)
                Spacer(minLength: 6)
                Text(window.percentLabel)
                    .font(.system(size: compact ? 20 : 24, weight: .black, design: .monospaced))
                    .foregroundStyle(color(for: window.tone, identity: accent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            segmentedProgress(window, identity: accent, track: track, segmentCount: 12, height: compact ? 6 : 8, spacing: 3)
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

    private var deepSeekPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DeepSeek 余额").font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.codexWidgetBlue)
            if let balance = entry.snapshot?.deepseek, balance.status == "ok", !balance.balanceInfos.isEmpty {
                ForEach(balance.balanceInfos) { info in
                    HStack(spacing: 3) {
                        Text(info.currency).font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 1)
                        Text(info.compactTotal).font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    }.foregroundStyle(.white)
                }
            } else {
                Text(entry.snapshot?.deepseek?.summary ?? "未同步")
                    .font(.system(size: 11)).foregroundStyle(Color.codexWidgetSecondary)
            }
        }
    }

    private func todayPanel(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日 token").font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.codexWidgetSecondary)
            Text(summary.todayLabel.replacingOccurrences(of: "今日 ", with: ""))
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.6)
            deepSeekPanel
        }
        .frame(width: 108, alignment: .leading)
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
        .configurationDisplayName("码伴 · CodeCompanion")
        .description("显示 Codex 额度与 DeepSeek 账户余额，可独立联网或点击刷新。")
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
