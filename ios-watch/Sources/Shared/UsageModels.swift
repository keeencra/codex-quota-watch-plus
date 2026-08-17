import Foundation

public enum UsageClientError: Error, LocalizedError {
    case invalidURL
    case badResponse(Int)
    case emptyToken
    case network(String, code: Int?)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Mac Agent URL"
        case .badResponse(let code):
            return "Mac Agent returned HTTP \(code)"
        case .emptyToken:
            return "WATCH_TOKEN is empty"
        case .network(let message, _):
            return "Network error: \(message)"
        case .invalidPayload(let message):
            return "Invalid /watch payload: \(message)"
        }
    }
}

public enum AppConstants {
    // Change this in every target's Signing & Capabilities > App Groups.
    public static let appGroupID = "group.com.example.CodexQuota"
    public static let snapshotKey = "latestSnapshotJSON"
    public static let macURLKey = "macAgentURL"
    public static let watchTokenKey = "watchToken"
    public static let autoRefreshKey = "autoRefreshEnabled"
    public static let refreshRequestKey = "refreshRequest"
    public static let directMacURLKey = "watchDirectMacAgentURL"
    public static let directWatchTokenKey = "watchDirectToken"
    public static let backgroundRefreshTaskID = "com.example.CodexQuota.refresh"
}

public enum WatchToken {
    private static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    private static let minimumLength = 24

    public static func sanitize(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let token = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= minimumLength,
              token.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return nil
        }
        return token
    }
}

public enum DiagnosticsText {
    public static func macURLStatus(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil else {
            return "invalid"
        }
        return "configured"
    }

    public static func tokenStatus(_ rawValue: String?) -> String {
        WatchToken.sanitize(rawValue) == nil ? "missing/invalid" : "configured"
    }
}

public struct PairingPayload: Equatable {
    public let macURL: String
    public let token: String

    public enum ParseError: Error, Equatable {
        case invalidFormat
        case invalidURL
        case invalidToken
    }

    public static func parse(_ rawValue: String) throws -> PairingPayload {
        guard let components = URLComponents(string: rawValue),
              components.scheme == "llmquota",
              components.host == "pair" else {
            throw ParseError.invalidFormat
        }

        let items = components.queryItems ?? []
        guard let macURL = items.first(where: { $0.name == "url" })?.value,
              let token = items.first(where: { $0.name == "token" })?.value else {
            throw ParseError.invalidFormat
        }

        guard let parsedURL = URLComponents(string: macURL),
              let scheme = parsedURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              parsedURL.host != nil else {
            throw ParseError.invalidURL
        }

        guard let token = WatchToken.sanitize(token) else {
            throw ParseError.invalidToken
        }

        return PairingPayload(macURL: macURL, token: token)
    }
}

public struct WatchAgentConfig: Equatable {
    public let macURL: String
    public let token: String

    public init(macURL: String, token: String) {
        self.macURL = macURL
        self.token = token
    }

    public static func make(macURL: String, token: String?) -> WatchAgentConfig? {
        let trimmedURL = macURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil else {
            return nil
        }
        guard let token = WatchToken.sanitize(token) else {
            return nil
        }
        return WatchAgentConfig(macURL: trimmedURL, token: token)
    }

    public static func make(from payload: [String: Any]) -> WatchAgentConfig? {
        make(
            macURL: payload[AppConstants.directMacURLKey] as? String ?? "",
            token: payload[AppConstants.directWatchTokenKey] as? String
        )
    }

    public var payload: [String: Any] {
        [
            AppConstants.directMacURLKey: macURL,
            AppConstants.directWatchTokenKey: token,
        ]
    }
}

public final class WatchAgentConfigStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard) {
        self.defaults = defaults
    }

    public func save(_ config: WatchAgentConfig) {
        defaults.set(config.macURL, forKey: AppConstants.directMacURLKey)
        defaults.set(config.token, forKey: AppConstants.directWatchTokenKey)
    }

    public func load() -> WatchAgentConfig? {
        WatchAgentConfig.make(
            macURL: defaults.string(forKey: AppConstants.directMacURLKey) ?? "",
            token: defaults.string(forKey: AppConstants.directWatchTokenKey)
        )
    }
}

public enum WatchRefreshRoute: Equatable {
    case cached
    case directRefreshing
    case directOK
    case noConfig
    case directFailed(String?)
    case iPhone

    public var label: String {
        switch self {
        case .cached:
            return "cached"
        case .directRefreshing:
            return "direct..."
        case .directOK:
            return "direct ok"
        case .noConfig:
            return "no config"
        case .directFailed(let detail):
            guard let detail, !detail.isEmpty else {
                return "direct failed"
            }
            return "direct \(detail)"
        case .iPhone:
            return "iphone"
        }
    }
}

public enum WatchRefreshErrorText {
    public static func directFailureDetail(_ error: Error) -> String? {
        guard let error = error as? UsageClientError else {
            return "net"
        }
        switch error {
        case .invalidURL:
            return "url"
        case .emptyToken:
            return "token"
        case .badResponse(let code):
            return "http\(code)"
        case .network(_, let code):
            return code.map(String.init) ?? "net"
        case .invalidPayload:
            return "payload"
        }
    }
}

public enum RefreshRequestPayload {
    public static let reasonKey = "refreshReason"
    public static let requestedAtKey = "refreshRequestedAt"

    public static func make(reason: String, requestedAt: Date = Date()) -> [String: Any] {
        [
            AppConstants.refreshRequestKey: true,
            reasonKey: reason,
            requestedAtKey: requestedAt.timeIntervalSince1970,
        ]
    }

    public static func isRefreshRequest(_ payload: [String: Any]) -> Bool {
        payload[AppConstants.refreshRequestKey] as? Bool == true
    }
}

public enum WatchRefreshPolicy {
    public static let refreshesOnAppear = true
    public static let foregroundRefreshIntervalSeconds: TimeInterval = 300
    public static let directRefreshTimeoutSeconds: TimeInterval = 10
    public static let requestsPhoneRelayOnOpen = true
    public static let phoneRelayDebounceSeconds: TimeInterval = 2

    public static func shouldRequestPhoneRelay(lastRequestAt: Date?, now: Date = Date()) -> Bool {
        guard let lastRequestAt else { return true }
        return now.timeIntervalSince(lastRequestAt) >= phoneRelayDebounceSeconds
    }
}

public struct WatchLayoutMetrics: Equatable {
    public enum SizeClass: String, Equatable {
        case compact
        case regular
        case spacious
    }

    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(width, 1)
        self.height = max(height, 1)
    }

    public var sizeClass: SizeClass {
        let shortSide = min(width, height)
        if shortSide < 185 {
            return .compact
        }
        if shortSide < 205 {
            return .regular
        }
        return .spacious
    }

    public var scale: Double {
        switch sizeClass {
        case .compact:
            return 0.88
        case .regular:
            return 0.95
        case .spacious:
            return 1.0
        }
    }

    public var outerHorizontalPadding: Double {
        switch sizeClass {
        case .compact:
            return 4
        case .regular:
            return 5
        case .spacious:
            return 6
        }
    }

    public var outerVerticalPadding: Double {
        switch sizeClass {
        case .compact:
            return 4
        case .regular, .spacious:
            return 5
        }
    }

    public var stackSpacing: Double {
        switch sizeClass {
        case .compact:
            return 6
        case .regular:
            return 7
        case .spacious:
            return 8
        }
    }

    public func hourlyHistogramSpacing(forBinCount binCount: Int) -> Double {
        if binCount >= 22 {
            return 1
        }
        if binCount >= 15 {
            return 2
        }
        return 3
    }

    public var cardPadding: Double {
        switch sizeClass {
        case .compact:
            return 7
        case .regular:
            return 8
        case .spacious:
            return 9
        }
    }

    public var cardSpacing: Double {
        switch sizeClass {
        case .compact:
            return 5
        case .regular:
            return 7
        case .spacious:
            return 8
        }
    }

    public var gaugeDiameter: Double {
        switch sizeClass {
        case .compact:
            return 64
        case .regular:
            return 72
        case .spacious:
            return 76
        }
    }

    public var codexHeroMinHeight: Double {
        max(height - (outerVerticalPadding * 2), 1)
    }

    public var codexPageTopOffset: Double {
        switch sizeClass {
        case .compact:
            return -22
        case .regular:
            return -26
        case .spacious:
            return -30
        }
    }

    public var quotaSubLabelFontSize: Double {
        switch sizeClass {
        case .compact:
            return 12
        case .regular, .spacious:
            return 13
        }
    }

    public var resetTitleFontSize: Double {
        switch sizeClass {
        case .compact:
            return 11
        case .regular, .spacious:
            return 12
        }
    }

    public var footerMetaFontSize: Double {
        switch sizeClass {
        case .compact:
            return 10
        case .regular, .spacious:
            return 11
        }
    }

    public var quotaHeadlineFontSize: Double {
        switch sizeClass {
        case .compact:
            return 31
        case .regular:
            return 36
        case .spacious:
            return 40
        }
    }

    public var dualWindowQuotaHeadlineFontSize: Double {
        switch sizeClass {
        case .compact:
            return 24
        case .regular:
            return 27
        case .spacious:
            return 30
        }
    }

    public var dualWindowSegmentHeight: Double {
        switch sizeClass {
        case .compact:
            return 8
        case .regular:
            return 9
        case .spacious:
            return 10
        }
    }

    public var segmentCount: Int {
        switch sizeClass {
        case .compact:
            return 14
        case .regular:
            return 18
        case .spacious:
            return 20
        }
    }
}

public struct WatchSnapshot: Codable, Equatable {
    public var updatedAt: String
    public var codex: ProviderUsage

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case codex
    }

    public init(updatedAt: String, codex: ProviderUsage) {
        self.updatedAt = updatedAt
        self.codex = codex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        codex = try container.decode(ProviderUsage.self, forKey: .codex)
    }

    public static let placeholder = WatchSnapshot(
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        codex: ProviderUsage.placeholder(status: "not_configured")
    )
}

public struct QuotaBucket: Codable, Equatable, Identifiable {
    public var id: String?
    public var label: String?
    public var remainingPercent: Double?
    public var usedPercent: Double?
    public var resetIn: String?
    public var window: String?
    public var status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case remainingPercent = "remaining_percent"
        case usedPercent = "used_percent"
        case resetIn = "reset_in"
        case window
        case status
    }

    public var stableID: String {
        id ?? label ?? window ?? UUID().uuidString
    }
}

public struct HourlyUsage: Codable, Equatable, Identifiable {
    public var hour: Int
    public var tokens: Int

    public var id: Int { hour }

    public func intensity(maxTokens: Int) -> Double {
        guard maxTokens > 0, tokens > 0 else {
            return 0
        }
        return min(max(Double(tokens) / Double(maxTokens), 0), 1)
    }
}

public struct CodexWindowSelection: Equatable {
    public var fiveHour: QuotaBucket?
    public var sevenDay: QuotaBucket?
}

public struct TwoHourTokenBin: Equatable, Identifiable {
    public var startHour: Int
    public var tokens: Int

    public var id: Int { startHour }

    public func intensity(maxTokens: Int) -> Double {
        guard maxTokens > 0, tokens > 0 else {
            return 0
        }
        return min(max(Double(tokens) / Double(maxTokens), 0), 1)
    }
}

public enum WatchDisplayData {
    public static func codexWindows(from buckets: [QuotaBucket]?) -> CodexWindowSelection {
        let selected = selectedCodexLimitBuckets(from: buckets ?? [])
        return CodexWindowSelection(
            fiveHour: selected.first { $0.window == "5h" } ?? selected.first,
            sevenDay: selected.first { $0.window == "7d" }
        )
    }

    public static func twoHourTokenBins(from hours: [HourlyUsage]) -> [TwoHourTokenBin] {
        twoHourTokenBins(from: hours, throughHour: 23)
    }

    public static func twoHourTokenBins(from hours: [HourlyUsage], throughHour: Int) -> [TwoHourTokenBin] {
        var byHour: [Int: Int] = [:]
        for hour in hours.suffix(24) {
            byHour[hour.hour, default: 0] += hour.tokens
        }
        let clampedHour = min(max(throughHour, 0), 23)
        let lastStartHour = min((clampedHour / 2) * 2, 22)
        return stride(from: 0, through: lastStartHour, by: 2).map { start in
            TwoHourTokenBin(startHour: start, tokens: (byHour[start] ?? 0) + (byHour[start + 1] ?? 0))
        }
    }

    public static func hourlyTokenBins(from hours: [HourlyUsage], throughHour: Int) -> [TwoHourTokenBin] {
        var byHour: [Int: Int] = [:]
        for hour in hours.suffix(24) {
            byHour[hour.hour, default: 0] += hour.tokens
        }
        let clampedHour = min(max(throughHour, 0), 23)
        return (0...clampedHour).map { hour in
            TwoHourTokenBin(startHour: hour, tokens: byHour[hour] ?? 0)
        }
    }

    private static func selectedCodexLimitBuckets(from buckets: [QuotaBucket]) -> [QuotaBucket] {
        guard !buckets.isEmpty else { return [] }

        let orderedGroups = groupedByLimitID(buckets)
        if let codex = orderedGroups.first(where: { $0.limitID == "codex" }) {
            return codex.buckets
        }

        return orderedGroups.min { lhs, rhs in
            lowestRemainingPercent(lhs.buckets) < lowestRemainingPercent(rhs.buckets)
        }?.buckets ?? orderedGroups.first?.buckets ?? []
    }

    private static func groupedByLimitID(_ buckets: [QuotaBucket]) -> [(limitID: String, buckets: [QuotaBucket])] {
        var order: [String] = []
        var grouped: [String: [QuotaBucket]] = [:]

        for bucket in buckets {
            let limitID = limitID(for: bucket)
            if grouped[limitID] == nil {
                order.append(limitID)
                grouped[limitID] = []
            }
            grouped[limitID]?.append(bucket)
        }

        return order.map { ($0, grouped[$0] ?? []) }
    }

    private static func limitID(for bucket: QuotaBucket) -> String {
        if let id = bucket.id?.split(separator: ":", maxSplits: 1).first {
            return String(id)
        }
        if let label = bucket.label?.split(separator: " ").first {
            return String(label)
        }
        return bucket.window ?? bucket.stableID
    }

    private static func lowestRemainingPercent(_ buckets: [QuotaBucket]) -> Double {
        buckets.compactMap(\.remainingPercent).min() ?? 101
    }
}

public struct ProviderUsage: Codable, Equatable {
    public var remainingPercent: Double?
    public var usedPercent: Double?
    public var resetIn: String?
    public var window: String?
    public var status: String
    public var source: String
    public var error: String?
    public var quotaUpdatedAt: String?
    public var estimateNote: String?
    public var estimateAnchorAt: String?
    public var estimateAnchorNote: String?
    public var todayTokens: Int
    public var todayInputTokens: Int?
    public var todayOutputTokens: Int?
    public var todayCacheTokens: Int?
    public var hourly: [HourlyUsage]
    public var buckets: [QuotaBucket]?

    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case usedPercent = "used_percent"
        case resetIn = "reset_in"
        case window
        case status
        case source
        case error
        case quotaUpdatedAt = "quota_updated_at"
        case estimateNote = "estimate_note"
        case estimateAnchorAt = "estimate_anchor_at"
        case estimateAnchorNote = "estimate_anchor_note"
        case todayTokens = "today_tokens"
        case todayInputTokens = "today_input_tokens"
        case todayOutputTokens = "today_output_tokens"
        case todayCacheTokens = "today_cache_tokens"
        case hourly
        case buckets
    }

    public init(
        remainingPercent: Double?,
        usedPercent: Double?,
        resetIn: String?,
        window: String?,
        status: String,
        source: String,
        error: String? = nil,
        quotaUpdatedAt: String?,
        estimateNote: String?,
        estimateAnchorAt: String?,
        estimateAnchorNote: String?,
        todayTokens: Int,
        todayInputTokens: Int?,
        todayOutputTokens: Int?,
        todayCacheTokens: Int?,
        hourly: [HourlyUsage] = [],
        buckets: [QuotaBucket]?
    ) {
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.resetIn = resetIn
        self.window = window
        self.status = status
        self.source = source
        self.error = error
        self.quotaUpdatedAt = quotaUpdatedAt
        self.estimateNote = estimateNote
        self.estimateAnchorAt = estimateAnchorAt
        self.estimateAnchorNote = estimateAnchorNote
        self.todayTokens = todayTokens
        self.todayInputTokens = todayInputTokens
        self.todayOutputTokens = todayOutputTokens
        self.todayCacheTokens = todayCacheTokens
        self.hourly = hourly
        self.buckets = buckets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remainingPercent = try container.decodeIfPresent(Double.self, forKey: .remainingPercent)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
        resetIn = try container.decodeIfPresent(String.self, forKey: .resetIn)
        window = try container.decodeIfPresent(String.self, forKey: .window)
        status = try container.decode(String.self, forKey: .status)
        source = try container.decode(String.self, forKey: .source)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        quotaUpdatedAt = try container.decodeIfPresent(String.self, forKey: .quotaUpdatedAt)
        estimateNote = try container.decodeIfPresent(String.self, forKey: .estimateNote)
        estimateAnchorAt = try container.decodeIfPresent(String.self, forKey: .estimateAnchorAt)
        estimateAnchorNote = try container.decodeIfPresent(String.self, forKey: .estimateAnchorNote)
        todayTokens = try container.decodeIfPresent(Int.self, forKey: .todayTokens) ?? 0
        todayInputTokens = try container.decodeIfPresent(Int.self, forKey: .todayInputTokens)
        todayOutputTokens = try container.decodeIfPresent(Int.self, forKey: .todayOutputTokens)
        todayCacheTokens = try container.decodeIfPresent(Int.self, forKey: .todayCacheTokens)
        hourly = try container.decodeIfPresent([HourlyUsage].self, forKey: .hourly) ?? []
        buckets = try container.decodeIfPresent([QuotaBucket].self, forKey: .buckets)
    }

    public static func placeholder(status: String) -> ProviderUsage {
        ProviderUsage(
            remainingPercent: nil,
            usedPercent: nil,
            resetIn: nil,
            window: nil,
            status: status,
            source: "placeholder",
            error: nil,
            quotaUpdatedAt: nil,
            estimateNote: nil,
            estimateAnchorAt: nil,
            estimateAnchorNote: nil,
            todayTokens: 0,
            todayInputTokens: 0,
            todayOutputTokens: 0,
            todayCacheTokens: 0,
            hourly: [],
            buckets: []
        )
    }
}

public final class SharedUsageStore {
    public static let shared = SharedUsageStore()

    private var defaults: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    public init() {}

    public func save(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: AppConstants.snapshotKey)
        defaults.synchronize()
    }

    public func load() -> WatchSnapshot {
        defaults.synchronize()
        guard let json = defaults.string(forKey: AppConstants.snapshotKey),
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }

    public func saveJSON(_ json: String) {
        defaults.set(json, forKey: AppConstants.snapshotKey)
        defaults.synchronize()
    }

    public func loadJSON() -> String? {
        defaults.synchronize()
        return defaults.string(forKey: AppConstants.snapshotKey)
    }
}

public enum NumberFormatters {
    public static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    public static func quotaHeadline(_ usage: ProviderUsage) -> String {
        if usage.status == "error" {
            return "error"
        }
        if usage.status == "not_configured" {
            return "setup"
        }
        if let remaining = usage.remainingPercent {
            return percent(remaining)
        }
        if usage.resetIn != nil || usage.window != nil || usage.todayTokens > 0 {
            return usage.status
        }
        return "--%"
    }

    public static func compactDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

public enum QuotaDisplayText {
    public static func isCriticalRemaining(_ remaining: Double?) -> Bool {
        (remaining ?? 100) <= 10
    }

    public static func remainingPercent(bucket: QuotaBucket?, fallback: ProviderUsage) -> Double? {
        bucket?.remainingPercent ?? fallback.remainingPercent
    }

    public static func usedPercent(bucket: QuotaBucket?, fallback: ProviderUsage) -> Double? {
        if let used = bucket?.usedPercent ?? fallback.usedPercent {
            return used
        }
        guard let remaining = remainingPercent(bucket: bucket, fallback: fallback) else {
            return nil
        }
        return max(0, min(100, 100 - remaining))
    }

    public static func usedLabel(bucket: QuotaBucket?, fallback: ProviderUsage) -> String {
        "已用 \(NumberFormatters.percent(usedPercent(bucket: bucket, fallback: fallback)))"
    }

    public static func resetLabel(bucket: QuotaBucket?, fallback: ProviderUsage) -> String {
        guard let reset = bucket?.resetIn ?? fallback.resetIn, !reset.isEmpty else {
            return "重置 --"
        }
        return "重置 \(reset)"
    }

    public static func updateLabel(snapshot: WatchSnapshot) -> String {
        "更新 \(NumberFormatters.compactDate(snapshot.updatedAt))"
    }

    public static func watchUpdateLabel(snapshot: WatchSnapshot, timeZone: TimeZone = .current) -> String {
        let rawUpdatedAt = snapshot.codex.quotaUpdatedAt ?? snapshot.updatedAt
        guard let updatedAt = parseDate(rawUpdatedAt) else {
            return "刷新 --"
        }
        return "刷新 \(watchTimeLabel(for: updatedAt, reference: updatedAt, timeZone: timeZone))"
    }

    public static func resetTimeLabel(
        bucket: QuotaBucket?,
        fallback: ProviderUsage,
        snapshot: WatchSnapshot,
        timeZone: TimeZone = .current
    ) -> String {
        guard
            let resetIn = bucket?.resetIn ?? fallback.resetIn,
            let interval = resetInterval(resetIn),
            let updatedAt = parseDate(snapshot.updatedAt)
        else {
            return "--"
        }
        let resetAt = updatedAt.addingTimeInterval(interval)
        return watchTimeLabel(for: resetAt, reference: updatedAt, timeZone: timeZone)
    }

    public static func codexFooterModelLabel(selection: CodexWindowSelection, fallback: ProviderUsage) -> String {
        if let codexBucket = fallback.buckets?.first(where: { limitID(for: $0).lowercased() == "codex" }),
           let label = modelLabel(for: codexBucket) {
            return label
        }
        for bucket in [selection.fiveHour, selection.sevenDay].compactMap({ $0 }) {
            if let label = modelLabel(for: bucket) {
                return label
            }
        }
        return codexFooterModelLabel(fallback)
    }

    public static func codexFooterModelLabel(_ usage: ProviderUsage) -> String {
        for bucket in usage.buckets ?? [] {
            if let label = modelLabel(for: bucket) {
                return label
            }
        }
        return "model --"
    }

    private static func modelLabel(for bucket: QuotaBucket) -> String? {
        if limitID(for: bucket).lowercased() == "codex" {
            return "GPT-5.5"
        }
        let label = cleanedModelLabel(bucket.label ?? "")
        if !label.isEmpty && !isGenericCodexLabel(label) {
            return label
        }
        return nil
    }

    private static func limitID(for bucket: QuotaBucket) -> String {
        if let id = bucket.id?.split(separator: ":", maxSplits: 1).first {
            return String(id)
        }
        if let label = bucket.label?.split(separator: " ").first {
            return String(label)
        }
        return bucket.window ?? bucket.stableID
    }

    private static func cleanedModelLabel(_ rawLabel: String) -> String {
        var label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [" secondary", " primary", " 5h", " 7d"]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where label.lowercased().hasSuffix(suffix) {
                label = String(label.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
        }
        return label
    }

    private static func isGenericCodexLabel(_ label: String) -> Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "codex"
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        let internetFormatter = ISO8601DateFormatter()
        if let date = internetFormatter.date(from: rawValue) {
            return date
        }
        internetFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return internetFormatter.date(from: rawValue)
    }

    private static func resetInterval(_ rawValue: String) -> TimeInterval? {
        var total = 0
        var digits = ""
        var matchedUnit = false
        for character in rawValue.lowercased() {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let value = Int(digits) else {
                continue
            }
            switch character {
            case "d":
                total += value * 86_400
                matchedUnit = true
            case "h":
                total += value * 3_600
                matchedUnit = true
            case "m":
                total += value * 60
                matchedUnit = true
            case "s":
                total += value
                matchedUnit = true
            default:
                break
            }
            if matchedUnit {
                digits = ""
            }
        }
        return matchedUnit ? TimeInterval(total) : nil
    }

    private static func watchTimeLabel(for date: Date, reference: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: reference) ? "HH:mm" : "MM/dd HH:mm"
        return formatter.string(from: date)
    }

}

public enum WidgetQuotaTone: Equatable {
    case normal
    case warning
    case critical
    case unavailable

    public static func make(remaining: Double?) -> WidgetQuotaTone {
        guard let remaining else { return .unavailable }
        if remaining <= 10 { return .critical }
        if remaining <= 25 { return .warning }
        return .normal
    }
}

public struct WidgetQuotaWindow: Equatable {
    public let title: String
    public let percentLabel: String
    public let refillLabel: String
    public let progress: Double
    public let tone: WidgetQuotaTone

    public init(
        title: String,
        bucket: QuotaBucket?,
        fallback: ProviderUsage,
        snapshot: WatchSnapshot? = nil,
        timeZone: TimeZone = .current
    ) {
        let remaining = QuotaDisplayText.remainingPercent(bucket: bucket, fallback: fallback)
        self.title = title
        self.percentLabel = remaining == nil ? "--%" : NumberFormatters.percent(remaining)
        if let snapshot {
            let resetTime = QuotaDisplayText.resetTimeLabel(
                bucket: bucket,
                fallback: fallback,
                snapshot: snapshot,
                timeZone: timeZone
            )
            self.refillLabel = resetTime == "--" ? "↻ --" : "↻ \(resetTime) 回满"
        } else {
            self.refillLabel = "↻ --"
        }
        self.progress = min(max((remaining ?? 0) / 100.0, 0), 1)
        self.tone = WidgetQuotaTone.make(remaining: remaining)
    }
}

public struct WidgetQuotaSummary: Equatable {
    public enum Status: Equatable {
        case setup
        case ready
        case error
    }

    public let title: String
    public let status: Status
    public let fiveHour: WidgetQuotaWindow
    public let sevenDay: WidgetQuotaWindow?
    public let updatedLabel: String
    public let modelLabel: String
    public let todayLabel: String
    public let tokenBreakdownLabel: String
    public let tokenBins: [TwoHourTokenBin]

    public init(snapshot: WatchSnapshot?, timeZone: TimeZone = .current) {
        title = "Codex Quota"
        guard let snapshot, snapshot.codex.status != "not_configured" else {
            status = .setup
            let fallback = ProviderUsage.placeholder(status: "not_configured")
            fiveHour = WidgetQuotaWindow(title: "5 小时", bucket: nil, fallback: fallback)
            sevenDay = nil
            updatedLabel = "等待同步"
            modelLabel = "model --"
            todayLabel = "今日 --"
            tokenBreakdownLabel = "In -- · Out -- · Cache --"
            tokenBins = []
            return
        }

        let selection = WatchDisplayData.codexWindows(from: snapshot.codex.buckets)
        status = snapshot.codex.status == "error" ? .error : .ready
        fiveHour = WidgetQuotaWindow(
            title: "5 小时",
            bucket: selection.fiveHour,
            fallback: snapshot.codex,
            snapshot: snapshot,
            timeZone: timeZone
        )
        if selection.sevenDay != nil {
            sevenDay = WidgetQuotaWindow(
                title: "7 天",
                bucket: selection.sevenDay,
                fallback: snapshot.codex,
                snapshot: snapshot,
                timeZone: timeZone
            )
        } else {
            sevenDay = nil
        }
        updatedLabel = QuotaDisplayText.watchUpdateLabel(snapshot: snapshot, timeZone: timeZone)
        modelLabel = QuotaDisplayText.codexFooterModelLabel(selection: selection, fallback: snapshot.codex)
        todayLabel = "今日 \(NumberFormatters.compactTokens(snapshot.codex.todayTokens))"
        tokenBreakdownLabel = [
            "In \(NumberFormatters.compactTokens(snapshot.codex.todayInputTokens ?? 0))",
            "Out \(NumberFormatters.compactTokens(snapshot.codex.todayOutputTokens ?? 0))",
            "Cache \(NumberFormatters.compactTokens(snapshot.codex.todayCacheTokens ?? 0))",
        ].joined(separator: " · ")
        tokenBins = WatchDisplayData.twoHourTokenBins(from: snapshot.codex.hourly)
    }
}

public enum WatchDisplayText {
    private static let staleAfterSeconds: TimeInterval = 15 * 60
    private static let oldAfterSeconds: TimeInterval = 2 * 60 * 60

    public static func providerBadge(_ usage: ProviderUsage, fallback: String) -> String {
        switch usage.status {
        case "error":
            return "error"
        case "not_configured":
            return "setup"
        default:
            return fallback
        }
    }

    public static func providerDetail(_ usage: ProviderUsage, fallback: String) -> String {
        switch usage.status {
        case "error":
            if !usage.source.isEmpty, usage.source != "unknown", usage.source != "placeholder" {
                return "\(usage.source) error"
            }
            return "quota error"
        case "not_configured":
            return "not configured"
        default:
            return usage.resetIn ?? usage.window ?? fallback
        }
    }

    public static func snapshotFooter(_ snapshot: WatchSnapshot, now: Date = Date()) -> String {
        guard let updatedAt = parseDate(snapshot.updatedAt) else {
            return "Updated --"
        }
        let age = max(0, now.timeIntervalSince(updatedAt))
        let relative = relativeAge(age)
        if age >= oldAfterSeconds {
            return "Old \(relative)"
        }
        if age >= staleAfterSeconds {
            return "Stale \(relative)"
        }
        return "Updated \(relative)"
    }

    public static func snapshotAlert(_ snapshot: WatchSnapshot, now: Date = Date()) -> String? {
        guard let updatedAt = parseDate(snapshot.updatedAt) else {
            return "Snapshot time unknown"
        }
        let age = max(0, now.timeIntervalSince(updatedAt))
        if age >= oldAfterSeconds {
            return "Old data: refresh on iPhone"
        }
        if age >= staleAfterSeconds {
            return "Stale data"
        }
        if snapshot.codex.status == "error" {
            return "Codex \(providerDetail(snapshot.codex, fallback: "error"))"
        }
        return nil
    }

    public static func snapshotRouteStatus(
        _ snapshot: WatchSnapshot,
        route: WatchRefreshRoute,
        now: Date = Date()
    ) -> String {
        guard let alert = snapshotAlert(snapshot, now: now) else {
            return route.label
        }
        if alert == "Stale data" {
            return "stale / \(route.label)"
        }
        if alert.hasPrefix("Old data") {
            return "old / \(route.label)"
        }
        return "\(alert) / \(route.label)"
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        let internetFormatter = ISO8601DateFormatter()
        if let date = internetFormatter.date(from: rawValue) {
            return date
        }
        internetFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return internetFormatter.date(from: rawValue)
    }

    private static func relativeAge(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded(.down))
        if rounded < 60 {
            return "now"
        }
        if rounded < 3_600 {
            return "\(rounded / 60)m ago"
        }
        if rounded < 86_400 {
            return "\(rounded / 3_600)h ago"
        }
        return "\(rounded / 86_400)d ago"
    }
}
