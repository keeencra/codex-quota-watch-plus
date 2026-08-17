import SwiftUI
import WatchKit

private struct WatchLayoutMetricsEnvironmentKey: EnvironmentKey {
    static let defaultValue = WatchLayoutMetrics(width: 198, height: 242)
}

extension EnvironmentValues {
    var watchLayoutMetrics: WatchLayoutMetrics {
        get { self[WatchLayoutMetricsEnvironmentKey.self] }
        set { self[WatchLayoutMetricsEnvironmentKey.self] = newValue }
    }
}

extension WatchLayoutMetrics {
    var cgScale: CGFloat {
        CGFloat(scale)
    }

    var cgOuterHorizontalPadding: CGFloat {
        CGFloat(outerHorizontalPadding)
    }

    var cgOuterVerticalPadding: CGFloat {
        CGFloat(outerVerticalPadding)
    }

    var cgStackSpacing: CGFloat {
        CGFloat(stackSpacing)
    }

    func font(_ size: CGFloat) -> CGFloat {
        max(8, CGFloat((Double(size) * scale).rounded()))
    }

    func space(_ size: CGFloat) -> CGFloat {
        max(1, size * cgScale)
    }
}

private extension Color {
    static let codexGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let codexBlue = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let codexAmber = Color(red: 1.000, green: 0.702, blue: 0.039)
    static let codexRed = Color(red: 1.000, green: 0.271, blue: 0.227)
    static let codexSecondary = Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.55)
}

struct WatchContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var receiver = WatchConnectivityReceiver.shared
    private let foregroundRefreshTimer = Timer.publish(
        every: WatchRefreshPolicy.foregroundRefreshIntervalSeconds,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let metrics = WatchLayoutMetrics(width: Double(proxy.size.width), height: Double(proxy.size.height))

            TabView {
                CodexQuotaPage(snapshot: receiver.snapshot)
                LocalTodayPage(usage: receiver.snapshot.codex)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .environment(\.watchLayoutMetrics, metrics)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if WatchRefreshPolicy.refreshesOnAppear {
                receiver.requestRefresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && WatchRefreshPolicy.refreshesOnAppear {
                receiver.requestRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WKExtension.applicationDidBecomeActiveNotification)) { _ in
            if WatchRefreshPolicy.refreshesOnAppear {
                receiver.requestRefresh()
            }
        }
        .onReceive(foregroundRefreshTimer) { _ in
            guard scenePhase == .active else { return }
            receiver.requestRefresh()
        }
    }
}

private struct CodexQuotaPage: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let snapshot: WatchSnapshot

    private var selection: CodexWindowSelection {
        WatchDisplayData.codexWindows(from: snapshot.codex.buckets)
    }

    var body: some View {
        let isDualWindow = selection.sevenDay != nil

        VStack(alignment: .leading, spacing: metrics.space(isDualWindow ? 4 : 10)) {
            WatchPageHeader(title: "Codex", badge: codexBadge, time: nil)

            VStack(alignment: .leading, spacing: metrics.space(isDualWindow ? 5 : 15)) {
                QuotaWindowBlock(
                    title: "5\u{5c0f}\u{65f6}",
                    bucket: selection.fiveHour,
                    fallback: snapshot.codex,
                    healthyColor: .codexGreen,
                    isCondensed: isDualWindow
                )

                if selection.sevenDay != nil {
                    QuotaWindowBlock(
                        title: "7\u{5929}",
                        bucket: selection.sevenDay,
                        fallback: snapshot.codex,
                        healthyColor: .codexBlue,
                        isCondensed: true
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: isDualWindow ? .top : .center)

            QuotaResetCards(selection: selection, fallback: snapshot.codex, snapshot: snapshot)

            QuotaPageFooter(snapshot: snapshot, selection: selection)
        }
        .padding(.horizontal, metrics.cgOuterHorizontalPadding + metrics.space(4))
        .padding(.top, CGFloat(metrics.codexPageTopOffset))
        .padding(.bottom, metrics.space(isDualWindow ? 10 : 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(Color.black)
    }

    private var codexBadge: String? {
        snapshot.codex.status == "ok" ? nil : WatchDisplayText.providerBadge(snapshot.codex, fallback: snapshot.codex.status)
    }

}

private struct WatchPageHeader: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let title: String
    let badge: String?
    let time: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.space(5)) {
            Text(title)
                .font(.system(size: metrics.font(17), weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let badge {
                Text(badge)
                    .font(.system(size: metrics.font(8), weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.codexSecondary)
                    .padding(.horizontal, metrics.space(5))
                    .padding(.vertical, metrics.space(2))
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let time {
                Text(time)
                    .font(.system(size: metrics.font(13), weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

private struct QuotaWindowBlock: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let title: String
    let bucket: QuotaBucket?
    let fallback: ProviderUsage
    let healthyColor: Color
    let isCondensed: Bool

    private var remaining: Double? {
        QuotaDisplayText.remainingPercent(bucket: bucket, fallback: fallback)
    }

    private var usedLabel: String {
        QuotaDisplayText.usedLabel(bucket: bucket, fallback: fallback)
    }

    private var accent: Color {
        guard let remaining else { return .codexSecondary }
        if QuotaDisplayText.isCriticalRemaining(remaining) { return .codexRed }
        if remaining <= 25 { return .codexAmber }
        return healthyColor
    }

    private var isCritical: Bool {
        QuotaDisplayText.isCriticalRemaining(remaining)
    }

    private var contentSpacing: CGFloat {
        metrics.space(isCondensed ? 3 : 6)
    }

    private var titleFontSize: CGFloat {
        metrics.font(isCondensed ? 12 : 14)
    }

    private var quotaFontSize: CGFloat {
        CGFloat(isCondensed ? metrics.dualWindowQuotaHeadlineFontSize : metrics.quotaHeadlineFontSize)
    }

    private var segmentHeight: CGFloat {
        metrics.space(CGFloat(isCondensed ? metrics.dualWindowSegmentHeight : 13))
    }

    private var footerFontSize: CGFloat {
        CGFloat(metrics.quotaSubLabelFontSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.space(6)) {
                Text(isCritical ? "\(title) \u{26a0}" : title)
                .font(.system(size: titleFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                Spacer(minLength: 4)
                Text(NumberFormatters.percent(remaining))
                    .font(.system(size: quotaFontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.55), radius: isCritical ? 6 : 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            LEDSegmentBar(value: remaining, activeColor: accent, segmentCount: metrics.segmentCount)
                .frame(height: segmentHeight)

            HStack(spacing: metrics.space(4)) {
                Text("\u{5269}\u{4f59}")
                    .foregroundStyle(Color.codexSecondary)
                Spacer(minLength: 0)
                Text(usedLabel)
                    .foregroundStyle(Color.codexSecondary)
            }
            .font(.system(size: footerFontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
    }
}

private struct QuotaResetCards: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let selection: CodexWindowSelection
    let fallback: ProviderUsage
    let snapshot: WatchSnapshot

    var body: some View {
        HStack(spacing: metrics.space(8)) {
            QuotaResetCard(
                title: "\u{91cd}\u{7f6e}(5h)",
                bucket: selection.fiveHour,
                fallback: fallback,
                snapshot: snapshot,
                accent: .codexGreen
            )
            if selection.sevenDay != nil {
                QuotaResetCard(
                    title: "\u{91cd}\u{7f6e}(7d)",
                    bucket: selection.sevenDay,
                    fallback: fallback,
                    snapshot: snapshot,
                    accent: .codexBlue
                )
            }
        }
    }
}

private struct QuotaResetCard: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let title: String
    let bucket: QuotaBucket?
    let fallback: ProviderUsage
    let snapshot: WatchSnapshot
    let accent: Color

    private var resetValue: String {
        QuotaDisplayText.resetTimeLabel(bucket: bucket, fallback: fallback, snapshot: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.space(2)) {
            Text(title)
                .font(.system(size: CGFloat(metrics.resetTitleFontSize), weight: .heavy, design: .rounded))
                .foregroundStyle(Color.codexSecondary)
            Text(resetValue)
                .font(.system(size: metrics.font(13), weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(resetValue == "--" ? Color.codexSecondary : accent)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, metrics.space(8))
        .padding(.vertical, metrics.space(6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        )
    }
}

private struct QuotaPageFooter: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let snapshot: WatchSnapshot
    let selection: CodexWindowSelection

    private var modelLabel: String {
        QuotaDisplayText.codexFooterModelLabel(selection: selection, fallback: snapshot.codex)
    }

    var body: some View {
        VStack(spacing: metrics.space(7)) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            HStack(alignment: .center, spacing: metrics.space(6)) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.codexGreen)
                    .frame(width: metrics.space(8), height: metrics.space(8))
                Text(modelLabel)
                    .font(.system(size: metrics.font(11), weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: metrics.space(8))
                Text(QuotaDisplayText.watchUpdateLabel(snapshot: snapshot))
                    .foregroundStyle(Color.codexSecondary)
                    .font(.system(size: CGFloat(metrics.footerMetaFontSize), weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }
}

private struct LEDSegmentBar: View {
    let value: Double?
    let activeColor: Color
    let segmentCount: Int

    private var activeSegments: Int {
        let clamped = min(max((value ?? 0) / 100, 0), 1)
        return Int((clamped * Double(segmentCount)).rounded(.up))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < activeSegments ? activeColor : activeColor.opacity(0.16))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Quota \(NumberFormatters.percent(value))")
    }
}

private struct LocalTodayPage: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let usage: ProviderUsage

    private var bins: [TwoHourTokenBin] {
        WatchDisplayData.hourlyTokenBins(from: usage.hourly, throughHour: currentHour)
    }

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var maxTokens: Int {
        max(bins.map(\.tokens).max() ?? 0, 1)
    }

    private var peakHour: Int? {
        bins.max { lhs, rhs in lhs.tokens < rhs.tokens }?.startHour
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.space(9)) {
            WatchPageHeader(title: "\u{4eca}\u{65e5}\u{7528}\u{91cf}", badge: nil, time: nil)

            VStack(alignment: .leading, spacing: metrics.space(1)) {
                Text(NumberFormatters.compactTokens(usage.todayTokens))
                    .font(.system(size: metrics.font(38), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("tokens")
                    .font(.system(size: metrics.font(11), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.codexSecondary)
            }

            Text("24 \u{5c0f}\u{65f6}\u{5206}\u{5e03}")
                .font(.system(size: metrics.font(11), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.codexSecondary)

            HourlyHistogram(bins: bins, maxTokens: maxTokens)
                .frame(height: metrics.space(70))

            HStack {
                Text("0h")
                Spacer()
                Text(peakLabel)
                Spacer()
                Text("now")
            }
            .font(.system(size: metrics.font(8), weight: .semibold, design: .rounded))
            .foregroundStyle(Color.codexSecondary)

            TokenTotalsRow(usage: usage)
        }
        .padding(.horizontal, metrics.cgOuterHorizontalPadding + metrics.space(4))
        .padding(.top, metrics.cgOuterVerticalPadding + metrics.space(6))
        .padding(.bottom, metrics.space(18))
        .foregroundStyle(.white)
        .background(Color.black)
    }

    private var peakLabel: String {
        guard let peakHour else { return "\u{5cf0}\u{503c} --" }
        return "\u{5cf0}\u{503c} \(String(format: "%02d:00", peakHour))"
    }
}

private struct HourlyHistogram: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let bins: [TwoHourTokenBin]
    let maxTokens: Int

    private var renderedBins: [TwoHourTokenBin] {
        bins
    }

    private var peakTokens: Int {
        renderedBins.map(\.tokens).max() ?? 0
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: CGFloat(metrics.hourlyHistogramSpacing(forBinCount: renderedBins.count))) {
            ForEach(renderedBins) { bin in
                let level = bin.intensity(maxTokens: maxTokens)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(bin.tokens == peakTokens && peakTokens > 0 ? Color.codexGreen : Color.codexGreen.opacity(0.48))
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.space(8 + CGFloat(level) * 58))
                    .opacity(bin.tokens == 0 ? 0.22 : 1)
                    .accessibilityLabel("\(bin.startHour):00 \(NumberFormatters.compactTokens(bin.tokens)) tokens")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct TokenTotalsRow: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let usage: ProviderUsage

    var body: some View {
        HStack(spacing: 0) {
            TokenTotal(label: "in", value: usage.todayInputTokens ?? 0, color: .codexGreen)
            TokenTotal(label: "out", value: usage.todayOutputTokens ?? 0, color: .codexBlue)
            TokenTotal(label: "cache", value: usage.todayCacheTokens ?? 0, color: Color(red: 0.42, green: 0.52, blue: 1.0))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct TokenTotal: View {
    @Environment(\.watchLayoutMetrics) private var metrics
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: metrics.font(12), weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(NumberFormatters.compactTokens(value))
                .font(.system(size: metrics.font(10), weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
