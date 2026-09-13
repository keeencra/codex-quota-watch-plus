import SwiftUI
import WidgetKit
import AppIntents

struct QuotaEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

#if os(macOS)
struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { .init(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(.init(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read()
        // A future entry marks old data even if macOS postpones the next refresh.
        let staleDate = max(now.addingTimeInterval(60), snapshot.updatedAt.addingTimeInterval(301))
        completion(Timeline(entries: [.init(date: now, snapshot: snapshot), .init(date: staleDate, snapshot: snapshot)], policy: .after(now.addingTimeInterval(900))))
    }
}

#endif

struct QuotaWidgetView: View {
    var entry: QuotaEntry
    var compact: Bool
    var expanded: Bool = false
    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var widgetDestination: URL? {
        #if os(macOS)
        return URL(string: "codexusagebar://refresh")
        #else
        return nil // WidgetKit opens the containing iPhone app.
        #endif
    }
    private let accent = Color.codexWidgetCredit
    private var stale: Bool { snapshot.isStale(at: entry.date) }
    private var status: String {
        if snapshot.updatedAt == .distantPast { return snapshot.codexError == "请先打开菜单栏应用" ? "打开应用以同步" : "共享读取失败 · 更新应用" }
        if stale { return "数据待更新" }
        if snapshot.codexError != nil { return "Codex 缓存 · 待同步" }
        return "已同步"
    }
    private func dateLabel(_ date: Date?, full: Bool = false) -> String {
        guard let date else { return "未提供" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = full ? "yyyy/MM/dd HH:mm" : "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    private var denseExpanded: Bool { snapshot.windows.count > 1 }
    private func countdown(_ date: Date?, expired: String) -> String {
        guard let date else { return "时间未提供" }
        let seconds = date.timeIntervalSince(entry.date)
        guard seconds > 0 else { return expired }
        let hours = Int(ceil(seconds / 3600))
        if hours >= 24 { return "\(hours / 24)天" + (hours % 24 == 0 ? "" : "\(hours % 24)小时") }
        return "\(hours)小时内"
    }
    private var orderedBalances: [WidgetSnapshot.Balance] {
        snapshot.balances.sorted {
            func rank(_ value: String) -> Int { value == "CNY" ? 0 : (value == "USD" ? 1 : 2) }
            return rank($0.currency) == rank($1.currency) ? $0.currency < $1.currency : rank($0.currency) < rank($1.currency)
        }
    }
    private var creditCount: String {
        snapshot.resetCredits.map { "\($0.availableCount) 张" } ?? "—"
    }
    private var expirationLabel: String {
        guard let credits = snapshot.resetCredits else { return "重置卡信息未提供" }
        guard credits.availableCount > 0 else { return "暂无可用重置卡" }
        guard let date = credits.expirations.min() else { return "到期时间未提供" }
        return (date <= entry.date ? "已到期 " : "到期 ") + dateLabel(date)
    }
    private func quotaColor(_ remaining: Int) -> Color {
        remaining <= 10 ? .codexWidgetRed : (remaining <= 25 ? .codexWidgetAmber : .codexWidgetGreen)
    }
    private func quotaBar(_ remaining: Int) -> some View {
        let count = compact ? 12 : 14
        let clamped = min(100, max(0, remaining))
        let filled = clamped > 0 ? max(1, clamped * count / 100) : 0
        return HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(quotaColor(clamped))
                    .opacity(index < filled ? 1 : 0.16)
            }
        }.frame(height: expanded ? 8 : (compact ? 5 : 4))
    }
    private func windowRow(_ window: WidgetSnapshot.Window) -> some View {
        VStack(alignment: .leading, spacing: expanded ? 4 : 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label == "周" ? "7天" : (window.label == "5h" ? "5小时" : window.label)).font(.system(size: compact ? 10 : 11)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text("\(window.remaining)%")
                    .font(.system(size: expanded ? (denseExpanded ? 28 : 36) : (compact ? 21 : 14), weight: .black, design: .rounded)).monospacedDigit().foregroundStyle(quotaColor(window.remaining))
            }
            quotaBar(window.remaining)
            Text("重置 " + dateLabel(window.resetsAt, full: false))
                .font(.system(size: compact ? 8 : (expanded ? (denseExpanded ? 10 : 12) : 8))).foregroundStyle(.secondary).lineLimit(1)
            if expanded {
                Text(window.resetsAt == nil ? "重置时间未提供" : (window.resetsAt! <= entry.date ? "已到重置时间 · 待刷新" : "距重置 " + countdown(window.resetsAt, expired: "待刷新")))
                    .font(.system(size: denseExpanded ? 10 : 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
    private var balanceView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DeepSeek 余额").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.codexWidgetBlue)
            if snapshot.balances.isEmpty {
                Text("—").font(.title3)
                Text(snapshot.balanceError == nil ? "等待同步" : "暂不可用").font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.balances.prefix(2).enumerated()), id: \.offset) { _, balance in
                    Text(balance.amount).font(.system(size: expanded ? 22 : 16, weight: .semibold, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                }
            }
        }
    }
    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    if snapshot.windows.isEmpty {
                        Text("等待 Codex 额度").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { _, window in
                        windowRow(window)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: denseExpanded ? 156 : 116)
                VStack(alignment: .leading, spacing: 8) {
                    Text("重置卡").font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                    Text(creditCount).font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                    if let credits = snapshot.resetCredits, credits.availableCount > 0, !credits.expirations.isEmpty {
                        ForEach(Array(credits.expirations.sorted().prefix(2).enumerated()), id: \.offset) { index, expiration in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expiration <= entry.date ? "卡 \(index + 1) · 已到期" : "卡 \(index + 1) · " + countdown(expiration, expired: "已到期") + "到期")
                                Text(dateLabel(expiration)).monospacedDigit()
                            }.font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.secondary)
                        }
                        if credits.expirations.count > 2 {
                            Text("更多记录见菜单栏").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(expirationLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(width: 126, alignment: .leading)
            }.frame(height: denseExpanded || (snapshot.resetCredits?.expirations.count ?? 0) > 1 ? 178 : 150, alignment: .center)
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DeepSeek 余额").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.codexWidgetBlue)
                    Spacer()
                    Text("官方 API 余额").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if snapshot.balances.isEmpty {
                    Text(snapshot.balanceError == "未配置 API Key" ? "未配置 DeepSeek" : "余额暂不可用 · 等待同步")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(orderedBalances.prefix(2).enumerated()), id: \.offset) { _, balance in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(balance.currency).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(balance.amount).font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .center)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: compact ? 4 : 8) {
                Text("Codex · " + (snapshot.plan == "Pro Lite" ? "Pro" : snapshot.plan))
                    .font(.system(size: compact ? 14 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if !compact && snapshot.updatedAt != .distantPast {
                    Text(snapshot.updatedAt, style: .time)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.codexWidgetSecondary).lineLimit(1)
                }
                #if WIDGET_GALLERY
                Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: compact ? 22 : 28, height: 24)
                #else
                Button(intent: RefreshQuotaWidgetIntent()) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: compact ? 22 : 28, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("刷新额度")
                #endif
            }.fixedSize(horizontal: false, vertical: true)
            if compact {
                if snapshot.windows.isEmpty {
                    Text("等待 Codex 额度").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { _, window in windowRow(window) }
                }
                Spacer(minLength: 0)
                HStack {
                    Text("重置卡").foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(creditCount).foregroundStyle(accent)
                }.font(.system(size: 9))
            } else if expanded {
                expandedLayout
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: expanded ? 8 : 3) {
                        if snapshot.windows.isEmpty {
                            Text("—").font(.title)
                            Text("等待 Codex 额度").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { _, window in windowRow(window) }
                        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                        HStack(spacing: 4) {
                            Text("Codex 重置卡").foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Text(creditCount).foregroundStyle(accent)
                        }.font(.system(size: expanded ? 11 : 9, weight: .medium))
                        if expanded, let credits = snapshot.resetCredits, !credits.expirations.isEmpty, credits.availableCount > 0 {
                            ForEach(Array(credits.expirations.sorted().prefix(3).enumerated()), id: \.offset) { index, expiration in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("卡 \(index + 1)" + (expiration <= entry.date ? " · 已到期" : " · 到期"))
                                    Text(dateLabel(expiration, full: true)).monospacedDigit()
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            if credits.expirations.count > 3 {
                                Text("更多记录见菜单栏详情").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(expirationLabel).font(.system(size: expanded ? 10 : 8)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Color.white.opacity(0.32)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        balanceView
                        Text("官方 API 余额").font(.system(size: 9)).foregroundStyle(.secondary)
                    }.frame(width: 112, alignment: .leading)
                }.frame(maxHeight: expanded ? 306 : 97)
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Circle().fill(stale || snapshot.codexError != nil ? Color.codexWidgetAmber : Color.codexWidgetGreen).frame(width: 4, height: 4)
                Text(status)
                if compact && snapshot.updatedAt != .distantPast {
                    Spacer(minLength: 2)
                    Text(snapshot.updatedAt, style: .time).monospacedDigit()
                }
            }.font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
        }
        .widgetURL(widgetDestination)
        .privacySensitive()
    }
}

#if os(macOS)
struct WidgetContent: View {
    @Environment(\.widgetFamily) private var family
    var entry: QuotaEntry
    var body: some View {
        Group {
            if family != .systemLarge {
                CodingQuotaWidgetView(entry: MacClassicProvider().classicEntry(entry.snapshot))

            } else {
                QuotaWidgetView(entry: entry, compact: family == .systemSmall, expanded: family == .systemLarge)
                    .padding(16)
            }
        }
        .containerBackground(Color.black, for: .widget)
        .environment(\.colorScheme, .dark)
    }
}

struct CodexUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.kind, provider: QuotaProvider()) { entry in
            WidgetContent(entry: entry)
        }
        .configurationDisplayName("码伴")
        .description("查看 Codex 剩余额度与 DeepSeek 官方余额。点击打开应用并同步。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main struct MacWidgetCollection: WidgetBundle {
    var body: some Widget {
        CodexUsageWidget()
    }
}
#endif
