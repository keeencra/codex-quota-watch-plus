import SwiftUI
import WidgetKit
import AppIntents

struct CodingQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    let entry: CodingQuotaWidgetEntry

    var body: some View {
        let summary = WidgetQuotaSummary(snapshot: entry.snapshot)
        Group {
            if entry.snapshot?.showsDeepSeekInWidget == true {
                switch family {
                case .systemMedium: medium(summary)
                default: smallWithDeepSeek(summary)
                }
            } else {
                switch family {
                case .systemMedium: medium(summary)
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
                                .foregroundStyle(color(for: window.tone, identity: .codexWidgetGreen))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        segmentedProgress(window,
                            identity: .codexWidgetGreen,
                            track: .codexWidgetGreenTrack,
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
                    accent: .codexWidgetGreen,
                    track: .codexWidgetGreenTrack,
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

    private func codexOnlyHeader(_ summary: WidgetQuotaSummary, showsMeta: Bool) -> some View {
        HStack(spacing: showsMeta ? 8 : 4) {
            Text("Codex · \(summary.planLabel)")
                .font(.system(size: showsMeta ? 17 : 14, weight: .semibold, design: .rounded))
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
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func codexOnlyTodayPanel(_ summary: WidgetQuotaSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.usageTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.codexWidgetSecondary)
            Text(entry.usageValue ?? summary.todayLabel.replacingOccurrences(of: "今日 ", with: ""))
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            if entry.showsTokenHistory {
                tokenBars(summary.tokenBins)
            } else {
                Text("明细见 Mac 菜单栏").font(.system(size: 9)).foregroundStyle(Color.codexWidgetSecondary)
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    private func medium(_ summary: WidgetQuotaSummary) -> some View {
        let hasBalance = entry.snapshot?.showsDeepSeekInWidget == true
        let credits = entry.snapshot?.resetCredits
        return VStack(alignment: .leading, spacing: 10) {
            header(summary, showsMeta: true)
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(summary.windows.enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(widgetTitle(window.title)).font(.system(size: 11)).foregroundStyle(Color.codexWidgetSecondary)
                                Spacer(minLength: 4)
                                Text(window.percentLabel)
                                    .font(.system(size: summary.windows.count > 1 ? 23 : 34, weight: .semibold, design: .rounded))
                                    .foregroundStyle(color(for: window.tone, identity: .codexWidgetGreen))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            segmentedProgress(window, identity: .codexWidgetGreen, track: .codexWidgetGreenTrack,
                                              segmentCount: 14, height: 5, spacing: 3)
                            if summary.windows.count == 1 {
                                Text(window.refillLabel).font(.system(size: 9)).foregroundStyle(Color.codexWidgetSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                            }
                        }
                    }
                    if summary.windows.isEmpty { Text("暂无额度数据").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(hasBalance ? "DeepSeek" : "重置卡")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hasBalance ? Color.codexWidgetBlue : Color.codexWidgetCredit)
                    if hasBalance {
                        if let balance = entry.snapshot?.deepseek, balance.status == "ok", !balance.balanceInfos.isEmpty {
                            ForEach(balance.balanceInfos) { info in
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(info.currency).font(.system(size: 9)).foregroundStyle(Color.codexWidgetSecondary)
                                    Spacer(minLength: 0)
                                    Text(info.compactTotal).font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                                }
                            }
                        } else {
                            Text(entry.snapshot?.deepseek?.summary ?? "未同步").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(credits.map { "\($0.availableCount) 张" } ?? "—")
                            .font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text(credits == nil ? "暂未提供数据" : "到期详情见账户总览")
                            .font(.system(size: 9)).foregroundStyle(Color.codexWidgetSecondary)
                    }
                }.frame(width: 112, alignment: .leading)
            }.frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                if hasBalance {
                    Text(credits.map { "重置卡 \($0.availableCount) 张" } ?? "重置卡 —")
                }
                Spacer(minLength: 0)
                Text(entry.usageTitle + " " + (entry.usageValue ?? summary.todayLabel.replacingOccurrences(of: "今日 ", with: "")))
            }.font(.system(size: 9)).foregroundStyle(Color.codexWidgetSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }.padding(16)
    }

    private func header(_ summary: WidgetQuotaSummary, showsMeta: Bool) -> some View {
        HStack(spacing: showsMeta ? 8 : 4) {
            Text("Codex · \(summary.planLabel)")
                .font(.system(size: showsMeta ? 17 : 14, weight: .semibold, design: .rounded))
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
        }.fixedSize(horizontal: false, vertical: true)
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
            Text(entry.usageTitle).font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.codexWidgetSecondary)
            Text(entry.usageValue ?? summary.todayLabel.replacingOccurrences(of: "今日 ", with: ""))
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
                    .fill(fill)
                    .opacity(index < activeSegments ? 1 : 0.16)
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
