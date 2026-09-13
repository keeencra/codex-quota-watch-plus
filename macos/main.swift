import AppKit
import Foundation
#if WIDGET_SUPPORT
import WidgetKit
#endif

struct ThreadUsage {
    let id: String
    let title: String
    let tokens: Int
    let model: String
    let updatedAtMs: Int64
}

struct UsageSnapshot {
    let current: ThreadUsage?
    let recent: [ThreadUsage]
    let totalRecentTokens: Int
    let checkedAt: Date
    let error: String?
}

struct AccountUsage {
    let shortWindow: AccountUsageWindow?
    let totalWindow: AccountUsageWindow?
    let resetCredits: ResetCredits?
    let planType: String?
    let lastSuccessAt: Date

    var windows: [AccountUsageWindow] { [shortWindow, totalWindow].compactMap { $0 } }
    var planLabel: String {
        switch planType?.lowercased() {
        case "prolite": return "Pro Lite"
        case "pro": return "Pro"
        case "plus": return "Plus"
        default: return planType?.capitalized ?? "Codex"
        }
    }
}

struct ResetCredits {
    let availableCount: Int
    let expirations: [Date]
}

struct AccountUsageWindow {
    let remainingPercent: Int
    let usedPercent: Int
    let windowLabel: String
    let resetsAt: Date?
    let durationMinutes: Double?
}

struct AppSnapshot {
    let accountUsage: AccountUsage?
    let threadUsage: UsageSnapshot
    let checkedAt: Date
    let nextRefreshAt: Date
    let accountError: String?
}

private enum UsageColors {
    static let good = NSColor(calibratedRed: 83 / 255, green: 145 / 255, blue: 105 / 255, alpha: 1)
    static let warning = NSColor(calibratedRed: 205 / 255, green: 151 / 255, blue: 67 / 255, alpha: 1)
    static let low = NSColor(calibratedRed: 184 / 255, green: 83 / 255, blue: 83 / 255, alpha: 1)
    static let empty = NSColor(calibratedRed: 246 / 255, green: 246 / 255, blue: 243 / 255, alpha: 1)
    static let unknown = NSColor(calibratedRed: 116 / 255, green: 121 / 255, blue: 128 / 255, alpha: 1)
    static let details = NSColor(calibratedRed: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1)
    static let detailText = NSColor(calibratedRed: 92 / 255, green: 95 / 255, blue: 99 / 255, alpha: 1)
    static let quotaBlue = NSColor(calibratedRed: 20 / 255, green: 128 / 255, blue: 245 / 255, alpha: 1)
    static let quotaAmber = NSColor(calibratedRed: 245 / 255, green: 156 / 255, blue: 33 / 255, alpha: 1)
    static let quotaCoral = NSColor(calibratedRed: 245 / 255, green: 74 / 255, blue: 64 / 255, alpha: 1)

    static func color(for remaining: Int?) -> NSColor {
        guard let remaining else { return unknown }
        if remaining <= 0 { return empty }
        if remaining <= 10 { return quotaCoral }
        if remaining <= 50 { return quotaAmber }
        return quotaBlue
    }

    static func textColor(on background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.62 ? NSColor(calibratedWhite: 0.16, alpha: 1) : .white
    }
}

private enum MenuBarQuotaGlyph {
    static func image(short: Int?, total: Int?) -> NSImage {
        let remaining = [short, total].compactMap { $0 }.min()
        return NSImage(size: NSSize(width: 16, height: 18), flipped: false) { _ in
            let center = NSPoint(x: 8, y: 9)
            let track = NSBezierPath(ovalIn: NSRect(x: 2, y: 3, width: 12, height: 12))
            track.lineWidth = 1.6
            NSColor.labelColor.withAlphaComponent(0.22).setStroke()
            track.stroke()
            if let remaining, remaining > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 6, startAngle: 90,
                              endAngle: 90 - 360 * CGFloat(remaining) / 100, clockwise: true)
                arc.lineWidth = 1.8
                arc.lineCapStyle = .round
                UsageColors.color(for: remaining).setStroke()
                arc.stroke()
            }
            NSColor.labelColor.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.5, y: 7.5, width: 3, height: 3)).fill()
            return true
        }
    }
}

final class AccountUsageReader: NSObject, URLSessionWebSocketDelegate {
    private let codexPath: String = {
        let candidates = [ProcessInfo.processInfo.environment["CODEX_BINARY"],
                          "/Applications/Codex.app/Contents/Resources/codex",
                          "/Applications/ChatGPT.app/Contents/Resources/codex"].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }()
    private let url = URL(string: "ws://127.0.0.1:47891")!
    private var serverProcess: Process?
    private let cacheURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex")
        .appendingPathComponent("codex-usage-bar-cache.json")

    func read() -> (AccountUsage?, String?) {
        if let usage = readFromServer() {
            saveCache(usage)
            return (usage, nil)
        }

        startServerIfNeeded()
        Thread.sleep(forTimeInterval: 1.0)

        if let usage = readFromServer() {
            saveCache(usage)
            return (usage, nil)
        }

        if let cached = loadCache() {
            return (cached, "使用上次成功缓存")
        }

        return (nil, "无法读取 account/rateLimits/read")
    }

    private func startServerIfNeeded() {
        guard serverProcess?.isRunning != true else { return }
        guard FileManager.default.fileExists(atPath: codexPath) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = [
            "-c", "features.code_mode_host=true",
            "app-server",
            "--analytics-default-enabled",
            "--listen", "ws://127.0.0.1:47891"
        ]

        let logURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("codex-usage-bar-appserver.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = handle
            process.standardError = handle
        }

        do {
            try process.run()
            serverProcess = process
        } catch {
            serverProcess = nil
        }
    }

    private func readFromServer() -> AccountUsage? {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        let semaphore = DispatchSemaphore(value: 0)
        var result: AccountUsage?

        task.resume()

        let messages: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "CodexUsageBar", "title": NSNull(), "version": "0.2.0"],
                    "capabilities": [
                        "experimentalApi": true,
                        "requestAttestation": false,
                        "optOutNotificationMethods": []
                    ]
                ]
            ],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read", "params": NSNull()]
        ]

        for message in messages {
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let text = String(data: data, encoding: .utf8) else {
                task.cancel(with: .invalid, reason: nil)
                return nil
            }
            task.send(.string(text)) { _ in }
        }

        receive(task: task, attemptsRemaining: 8) { usage in
            result = usage
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
        return result
    }

    private func receive(task: URLSessionWebSocketTask, attemptsRemaining: Int, completion: @escaping (AccountUsage?) -> Void) {
        guard attemptsRemaining > 0 else {
            completion(nil)
            return
        }

        task.receive { [weak self] message in
            guard let self else {
                completion(nil)
                return
            }

            switch message {
            case .success(.string(let text)):
                if let usage = self.parseUsageResponse(text) {
                    completion(usage)
                } else {
                    self.receive(task: task, attemptsRemaining: attemptsRemaining - 1, completion: completion)
                }
            case .success:
                self.receive(task: task, attemptsRemaining: attemptsRemaining - 1, completion: completion)
            case .failure:
                completion(nil)
            }
        }
    }

    func parseUsageResponse(_ text: String) -> AccountUsage? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? Int,
              id == 2,
              let response = object["result"] as? [String: Any] else {
            return nil
        }

        let limit = ((response["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any])
            ?? (response["rateLimits"] as? [String: Any])
        guard let limit else {
            return nil
        }

        let windows = [
            parseWindow(limit["primary"] as? [String: Any]),
            parseWindow(limit["secondary"] as? [String: Any])
        ].compactMap { $0 }

        guard !windows.isEmpty else { return nil }

        let sortedWindows = windows.sorted {
            ($0.durationMinutes ?? Double.greatestFiniteMagnitude) < ($1.durationMinutes ?? Double.greatestFiniteMagnitude)
        }
        // A Pro account may expose only a weekly primary window.
        // Classify by actual duration instead of assuming primary means five hours.
        let onlyLongWindow = sortedWindows.count == 1 && (sortedWindows[0].durationMinutes ?? 0) >= 1440
        let shortWindow = onlyLongWindow ? nil : sortedWindows.first
        let totalWindow = onlyLongWindow ? sortedWindows.first : (sortedWindows.count > 1 ? sortedWindows.last : nil)
        let plan = limit["planType"] as? String
        let resetCredits = parseResetCredits(response["rateLimitResetCredits"] as? [String: Any])

        return AccountUsage(
            shortWindow: shortWindow,
            totalWindow: totalWindow,
            resetCredits: resetCredits,
            planType: plan,
            lastSuccessAt: Date()
        )
    }

    private func parseResetCredits(_ object: [String: Any]?) -> ResetCredits? {
        guard let object else { return nil }
        let availableCount = object["availableCount"] as? Int ?? 0
        let credits = object["credits"] as? [[String: Any]] ?? []
        let expirations = credits.compactMap { credit -> Date? in
            guard let expiresAt = credit["expiresAt"] as? Double else { return nil }
            return Date(timeIntervalSince1970: expiresAt)
        }.sorted()
        return ResetCredits(availableCount: availableCount, expirations: expirations)
    }

    private func parseWindow(_ window: [String: Any]?) -> AccountUsageWindow? {
        guard let window,
              let used = window["usedPercent"] as? Double else {
            return nil
        }

        let duration = window["windowDurationMins"] as? Double
        let resetsAt = (window["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let remaining = max(0, min(100, Int((100.0 - used).rounded())))

        return AccountUsageWindow(
            remainingPercent: remaining,
            usedPercent: Int(used.rounded()),
            windowLabel: windowLabel(minutes: duration),
            resetsAt: resetsAt,
            durationMinutes: duration
        )
    }

    private func loadCache() -> AccountUsage? {
        guard let data = try? Data(contentsOf: cacheURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int,
              version == 1,
              let lastSuccess = object["lastSuccessAt"] as? Double else {
            return nil
        }

        return AccountUsage(
            shortWindow: decodeCachedWindow(object["shortWindow"] as? [String: Any]),
            totalWindow: decodeCachedWindow(object["totalWindow"] as? [String: Any]),
            resetCredits: decodeCachedResetCredits(object["resetCredits"] as? [String: Any]),
            planType: object["planType"] as? String,
            lastSuccessAt: Date(timeIntervalSince1970: lastSuccess)
        )
    }

    private func saveCache(_ usage: AccountUsage) {
        var object: [String: Any] = [
            "version": 1,
            "lastSuccessAt": usage.lastSuccessAt.timeIntervalSince1970
        ]
        if let shortWindow = encodeCachedWindow(usage.shortWindow) {
            object["shortWindow"] = shortWindow
        }
        if let totalWindow = encodeCachedWindow(usage.totalWindow) {
            object["totalWindow"] = totalWindow
        }
        if let resetCredits = encodeCachedResetCredits(usage.resetCredits) {
            object["resetCredits"] = resetCredits
        }
        if let planType = usage.planType {
            object["planType"] = planType
        }

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = cacheURL.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try FileManager.default.removeItem(at: cacheURL)
            }
            try FileManager.default.moveItem(at: temporary, to: cacheURL)
        } catch {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func encodeCachedWindow(_ window: AccountUsageWindow?) -> [String: Any]? {
        guard let window else { return nil }
        var object: [String: Any] = [
            "remainingPercent": window.remainingPercent,
            "usedPercent": window.usedPercent,
            "windowLabel": window.windowLabel
        ]
        if let resetsAt = window.resetsAt {
            object["resetsAt"] = resetsAt.timeIntervalSince1970
        }
        if let duration = window.durationMinutes {
            object["durationMinutes"] = duration
        }
        return object
    }

    private func decodeCachedWindow(_ object: [String: Any]?) -> AccountUsageWindow? {
        guard let object,
              let remaining = object["remainingPercent"] as? Int,
              let used = object["usedPercent"] as? Int,
              let label = object["windowLabel"] as? String,
              (0...100).contains(remaining),
              (0...100).contains(used) else {
            return nil
        }

        let resetsAt = (object["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let duration = object["durationMinutes"] as? Double
        return AccountUsageWindow(
            remainingPercent: remaining,
            usedPercent: used,
            windowLabel: label,
            resetsAt: resetsAt,
            durationMinutes: duration
        )
    }

    private func encodeCachedResetCredits(_ credits: ResetCredits?) -> [String: Any]? {
        guard let credits else { return nil }
        return [
            "availableCount": credits.availableCount,
            "expirations": credits.expirations.map { $0.timeIntervalSince1970 }
        ]
    }

    private func decodeCachedResetCredits(_ object: [String: Any]?) -> ResetCredits? {
        guard let object else { return nil }
        let availableCount = object["availableCount"] as? Int ?? 0
        let expirations = (object["expirations"] as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
            .sorted()
        return ResetCredits(availableCount: availableCount, expirations: expirations)
    }

    private func windowLabel(minutes: Double?) -> String {
        guard let minutes else { return "用量窗口" }
        if minutes >= 10080 {
            return "\(Int((minutes / 10080).rounded()))周"
        }
        if minutes >= 1440 {
            return "\(Int((minutes / 1440).rounded()))天"
        }
        if minutes >= 60 {
            return "\(Int((minutes / 60).rounded()))小时"
        }
        return "\(Int(minutes.rounded()))分钟"
    }
}

final class CodexUsageReader {
    private let codexHome: String
    private let contextLimit = 244_800

    init(codexHome: String = NSHomeDirectory() + "/.codex") {
        self.codexHome = codexHome
    }

    func read() -> UsageSnapshot {
        let dbPath = codexHome + "/state_5.sqlite"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return UsageSnapshot(current: nil, recent: [], totalRecentTokens: 0, checkedAt: Date(), error: "找不到 \(dbPath)")
        }

        let sql = """
        select id, replace(replace(title, char(10), ' '), '|', '/'), tokens_used, coalesce(model,''), coalesce(updated_at_ms, updated_at * 1000)
        from threads
        order by coalesce(updated_at_ms, updated_at * 1000) desc
        limit 8;
        """

        do {
            let output = try run("/usr/bin/sqlite3", args: ["-separator", "\t", dbPath, sql])
            let rows = output
                .split(separator: "\n")
                .compactMap(parseRow)
            let total = rows.reduce(0) { $0 + $1.tokens }
            return UsageSnapshot(current: rows.first, recent: rows, totalRecentTokens: total, checkedAt: Date(), error: nil)
        } catch {
            return UsageSnapshot(current: nil, recent: [], totalRecentTokens: 0, checkedAt: Date(), error: error.localizedDescription)
        }
    }

    func contextRemainingPercent(for thread: ThreadUsage?) -> Int? {
        guard let thread else { return nil }
        let remaining = max(0, contextLimit - thread.tokens)
        return Int((Double(remaining) / Double(contextLimit) * 100).rounded())
    }

    private func parseRow(_ row: Substring) -> ThreadUsage? {
        let parts = row.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 5,
              let tokens = Int(parts[2]),
              let updated = Int64(parts[4]) else {
            return nil
        }

        return ThreadUsage(
            id: String(parts[0]),
            title: String(parts[1]).isEmpty ? "未命名任务" : String(parts[1]),
            tokens: tokens,
            model: String(parts[3]).isEmpty ? "unknown" : String(parts[3]),
            updatedAtMs: updated
        )
    }

    private func run(_ launchPath: String, args: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "CodexUsageReader",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
        return output
    }
}

struct DeepSeekBalance: Decodable {
    struct Entry: Decodable {
        let currency: String
        let total_balance: String
        let granted_balance: String
        let topped_up_balance: String
        var display: String {
            let symbol = currency == "CNY" ? "¥" : (currency == "USD" ? "$" : currency + " ")
            return symbol + total_balance
        }
    }
    let is_available: Bool
    let balance_infos: [Entry]

    // Prefer a funded CNY account, then another funded currency; never add currencies.
    var menuBarAmount: String {
        let positive = balance_infos.filter { (Decimal(string: $0.total_balance) ?? 0) > 0 }
        let entry = positive.first { $0.currency == "CNY" } ?? positive.first
            ?? balance_infos.first { $0.currency == "CNY" } ?? balance_infos.first
        return entry?.display ?? "—"
    }
}

enum MenuBarSummary {
    static func title(codex: String, balance: DeepSeekBalance?) -> NSAttributedString {
        let text = NSMutableAttributedString(string: codex, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        ])
        text.append(NSAttributedString(string: " · ", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        text.append(NSAttributedString(string: "DS " + (balance?.menuBarAmount ?? "—"), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        ]))
        return text
    }
}

final class DeepSeekBalanceReader {
    // Reuse CodeCompanion's local configuration without copying keys into the app or widget.
    static func configuredKey(environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        if let value = environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        for path in ["Library/Application Support/CodexQuotaWatch/deepseek-api-key", ".codex/secrets/deepseek-api-key"] {
            if let value = try? String(contentsOf: home.appendingPathComponent(path), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return ""
    }

    func read(completion: @escaping (DeepSeekBalance?, String?) -> Void) {
        let key = Self.configuredKey()
        guard !key.isEmpty else { completion(nil, "未配置 API Key"); return }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.timeoutInterval = 12
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            guard error == nil else { completion(nil, "网络连接失败"); return }
            guard let http = response as? HTTPURLResponse else { completion(nil, "响应无效"); return }
            guard http.statusCode == 200 else {
                completion(nil, http.statusCode == 401 ? "API Key 无效" : "查询失败（HTTP \(http.statusCode)）")
                return
            }
            guard let data, let balance = try? JSONDecoder().decode(DeepSeekBalance.self, from: data),
                  !balance.balance_infos.isEmpty else { completion(nil, "余额数据无效"); return }
            completion(balance, nil)
        }.resume()
    }
}

final class QuotaDashboardView: NSView {
    let snapshot: AppSnapshot
    let balance: DeepSeekBalance?
    let balanceError: String?
    let balanceDate: Date?
    private let ink = NSColor(calibratedWhite: 0.94, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.54, green: 0.60, blue: 0.69, alpha: 1)
    private let purple = NSColor(calibratedRed: 0.63, green: 0.57, blue: 1, alpha: 1)
    private let teal = NSColor(calibratedRed: 0.35, green: 0.83, blue: 0.79, alpha: 1)
    override var isFlipped: Bool { true }
    init(snapshot: AppSnapshot, balance: DeepSeekBalance?, error: String?, date: Date?) {
        self.snapshot = snapshot; self.balance = balance; balanceError = error; balanceDate = date
        let rows = max(1, snapshot.accountUsage?.windows.count ?? 0)
        let currencies = max(1, balance?.balance_infos.count ?? 0)
        super.init(frame: NSRect(x: 0, y: 0, width: 368, height: 352 + rows * 70 + currencies * 62))
        setAccessibilityElement(true)
        setAccessibilityLabel("AI 额度概览。完整数值可在用量与任务详情菜单中查看。")
    }
    required init?(coder: NSCoder) { fatalError() }
    private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat = 310, size: CGFloat = 12,
                      color: NSColor? = nil, weight: NSFont.Weight = .regular, mono: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size + 7), withAttributes: [
            .font: mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color ?? ink, .paragraphStyle: paragraph
        ])
    }
    private func card(y: CGFloat, height: CGFloat) {
        let path = NSBezierPath(roundedRect: NSRect(x: 14, y: y, width: 340, height: height), xRadius: 13, yRadius: 13)
        NSColor(calibratedRed: 0.065, green: 0.09, blue: 0.135, alpha: 1).setFill(); path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.09).setStroke(); path.lineWidth = 1; path.stroke()
    }
    private func stamp(_ date: Date?) -> String {
        guard let date else { return "待更新" }
        let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"; return formatter.string(from: date)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.052, blue: 0.083, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 14, yRadius: 14).fill()
        text("AI 额度", x: 24, y: 18, size: 19, weight: .bold)
        text("USAGE MONITOR", x: 24, y: 46, size: 9, color: muted, weight: .medium)
        text("每 60 秒刷新", x: 250, y: 24, width: 95, size: 10, color: muted)
        var y: CGFloat = 76
        let windows = snapshot.accountUsage?.windows ?? []
        let ch = CGFloat(72 + max(1, windows.count) * 70)
        card(y: y, height: ch)
        text("◈", x: 28, y: y + 15, size: 20, color: purple)
        text("Codex", x: 56, y: y + 18, size: 14, weight: .semibold)
        let plan = snapshot.accountUsage?.planType == "prolite" ? "Pro" : (snapshot.accountUsage?.planLabel ?? "—")
        text(plan, x: 275, y: y + 19, width: 60, size: 11, color: purple, weight: .semibold)
        var row = y + 52
        if windows.isEmpty { text("额度暂不可用", x: 28, y: row, color: muted) }
        for window in windows {
            let label = window.windowLabel == "1周" ? "周额度" : (window.windowLabel == "5小时" ? "5h 额度" : window.windowLabel)
            text(label, x: 28, y: row, size: 11, color: muted)
            text("\(window.remainingPercent)% 剩余", x: 238, y: row - 2, width: 102, size: 14, weight: .semibold, mono: true)
            let tint = window.remainingPercent <= 10 ? NSColor.systemRed : (window.remainingPercent <= 50 ? NSColor.systemOrange : purple)
            for index in 0..<24 {
                let segment = NSBezierPath(roundedRect: NSRect(x: 28 + CGFloat(index) * 13, y: row + 25, width: 10, height: 5), xRadius: 1.5, yRadius: 1.5)
                let fraction = max(0, min(1, CGFloat(window.remainingPercent) / 100 * 24 - CGFloat(index)))
                tint.withAlphaComponent(0.12).setFill(); segment.fill()
                if fraction > 0 {
                    tint.setFill()
                    NSBezierPath(roundedRect: NSRect(x: 28 + CGFloat(index) * 13, y: row + 25, width: 10 * fraction, height: 5), xRadius: 1, yRadius: 1).fill()
                }
            }
            text("重置  " + stamp(window.resetsAt), x: 28, y: row + 38, size: 10, color: muted)
            row += 70
        }
        let state = snapshot.accountError == nil ? "已更新 " + stamp(snapshot.accountUsage?.lastSuccessAt) : "缓存数据 · 暂未连接"
        text(state, x: 28, y: y + ch - 20, size: 9, color: muted)
        y += ch + 12
        let dh = CGFloat(62 + max(1, balance?.balance_infos.count ?? 0) * 62)
        card(y: y, height: dh)
        text("◉", x: 28, y: y + 15, size: 19, color: teal)
        text("DeepSeek", x: 56, y: y + 18, size: 14, weight: .semibold)
        text(balance == nil ? "未连接" : (balance!.is_available ? "可用" : "余额不足"), x: 276, y: y + 20, width: 65, size: 10, color: balance?.is_available == false ? .systemOrange : teal)
        row = y + 48
        if let balance {
            for entry in balance.balance_infos {
                text(entry.display, x: 28, y: row, size: 24, weight: .semibold, mono: true)
                text(entry.currency, x: 287, y: row + 9, width: 50, size: 10, color: muted)
                text("充值 \(entry.topped_up_balance)  ·  赠送 \(entry.granted_balance)", x: 28, y: row + 33, size: 10, color: muted)
                row += 62
            }
        } else { text(balanceError ?? "正在查询余额", x: 28, y: row + 5, color: muted) }
        y += dh + 12
        card(y: y, height: 70)
        text("最近任务用量", x: 28, y: y + 14, size: 11, color: muted)
        let tokens = snapshot.threadUsage.totalRecentTokens
        let count = tokens >= 1_000_000 ? String(format: "%.2fM", Double(tokens) / 1_000_000) : (tokens >= 1000 ? String(format: "%.1fK", Double(tokens) / 1000) : String(tokens))
        text(count + " tokens", x: 28, y: y + 33, size: 18, weight: .semibold, mono: true)
        text("最近 8 个任务", x: 243, y: y + 38, width: 96, size: 10, color: muted)
        text("本机读取  ·  DeepSeek " + stamp(balanceDate), x: 24, y: y + 85, size: 9, color: muted)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let accountReader = AccountUsageReader()
    private let reader = CodexUsageReader()
    private let deepSeekReader = DeepSeekBalanceReader()
    private var deepSeekBalance: DeepSeekBalance?
    private var deepSeekError: String? = "正在查询"
    private var deepSeekUpdatedAt: Date?
    private var latestSnapshot: AppSnapshot?
    private var deepSeekLoading = false
    private var timer: Timer?
    private var widgetError: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.toolTip = "码伴 Mac · Codex 本地用量"
        statusItem.button?.imagePosition = .imageLeft
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        if !deepSeekLoading {
            deepSeekLoading = true
            deepSeekReader.read { [weak self] balance, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.deepSeekLoading = false
                    self.deepSeekBalance = balance
                    self.deepSeekError = error
                    self.deepSeekUpdatedAt = balance == nil ? nil : Date()
                    if let snapshot = self.latestSnapshot {
                        self.updateTitle(snapshot)
                        self.updateMenu(snapshot)
                    }
                }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            let threadUsage = self.reader.read()
            let account = self.accountReader.read()
            let snapshot = AppSnapshot(
                accountUsage: account.0,
                threadUsage: threadUsage,
                checkedAt: Date(),
                nextRefreshAt: Date().addingTimeInterval(60),
                accountError: account.1
            )
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
                self.updateTitle(snapshot)
                self.updateMenu(snapshot)
            }
        }
    }

    private func updateTitle(_ snapshot: AppSnapshot) {
        #if WIDGET_SUPPORT
        let widget = WidgetSnapshot(updatedAt: Date(), codexUpdatedAt: snapshot.accountUsage?.lastSuccessAt,
            plan: snapshot.accountUsage?.planLabel ?? "Codex",
            windows: snapshot.accountUsage?.windows.map { .init(label: $0.windowLabel == "5小时" ? "5h" : ($0.windowLabel == "1周" ? "周" : $0.windowLabel), remaining: $0.remainingPercent, resetsAt: $0.resetsAt) } ?? [],
            balances: deepSeekBalance?.balance_infos.map { .init(currency: $0.currency, amount: $0.display) } ?? [],
            codexError: snapshot.accountError, balanceError: deepSeekError,
            resetCredits: snapshot.accountUsage?.resetCredits.map { .init(availableCount: $0.availableCount, expirations: $0.expirations.sorted()) }, recentTokens: snapshot.threadUsage.totalRecentTokens)
        do {
            try WidgetSnapshotStore.write(widget)
            widgetError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch { widgetError = "小组件同步失败，请检查共享容器与签名" }
        #endif
        defer {
            if let button = statusItem.button {
                button.attributedTitle = MenuBarSummary.title(codex: button.title, balance: deepSeekBalance)
                let amount = deepSeekBalance?.balance_infos.map { $0.display }.joined(separator: " / ") ?? "—"
                button.toolTip = (button.toolTip ?? "Codex") + "\nDeepSeek " + (deepSeekError ?? amount)
                button.setAccessibilityLabel(button.toolTip)
            }
        }
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        if let accountUsage = snapshot.accountUsage {
            let shortRemaining = accountUsage.shortWindow?.remainingPercent
            let totalRemaining = accountUsage.totalWindow?.remainingPercent
            statusItem.button?.image = MenuBarQuotaGlyph.image(short: shortRemaining, total: totalRemaining)
            let values = accountUsage.windows.map {
                let label = $0.windowLabel == "1周" ? "周" : ($0.windowLabel == "5小时" ? "5h" : $0.windowLabel)
                return "\(label)\($0.remainingPercent)%"
            }
            let plan = accountUsage.planType?.lowercased() == "prolite" ? "Pro" : accountUsage.planLabel
            statusItem.button?.title = "\(plan) " + (values.isEmpty ? "—" : values.joined(separator: " "))
            statusItem.button?.toolTip = "Codex \(accountUsage.planLabel) 剩余额度：" + values.joined(separator: " · ")
            return
        }

        statusItem.button?.image = MenuBarQuotaGlyph.image(short: nil, total: nil)
        guard snapshot.threadUsage.error == nil, let current = snapshot.threadUsage.current else {
            statusItem.button?.title = " --%"
            statusItem.button?.toolTip = "Codex 用量读取中"
            return
        }

        if let remaining = reader.contextRemainingPercent(for: current) {
            statusItem.button?.title = " \(remaining)%"
            statusItem.button?.toolTip = "当前任务上下文剩余 \(remaining)%"
        } else {
            statusItem.button?.title = " \(formatTokens(current.tokens))"
            statusItem.button?.toolTip = "当前任务已用 \(formatTokens(current.tokens)) tokens"
        }
    }

    private func updateMenu(_ snapshot: AppSnapshot) {
        let menu = NSMenu()
        menu.addItem(disabled("DeepSeek · 官方 API"))
        if let balance = deepSeekBalance {
            for entry in balance.balance_infos {
                menu.addItem(disabled("余额：\(entry.display)（\(entry.currency)）"))
                menu.addItem(disabled("充值：\(entry.topped_up_balance) · 赠送：\(entry.granted_balance)"))
            }
            menu.addItem(disabled(balance.is_available ? "状态：可用" : "状态：余额不足"))
            if let date = deepSeekUpdatedAt {
                menu.addItem(disabled("更新：\(timeFormatter.string(from: date))"))
            }
        } else {
            menu.addItem(disabled(deepSeekError ?? "正在查询"))
        }
        menu.addItem(.separator())

        if let accountUsage = snapshot.accountUsage {
            menu.addItem(disabled("剩余用量"))
            if let short = accountUsage.shortWindow {
                menu.addItem(disabled("\(short.windowLabel)    \(short.remainingPercent)%    重置：\(resetDateTimeFullLabel(short.resetsAt))"))
                menu.addItem(disabled("\(short.windowLabel)已用：\(short.usedPercent)%"))
            }
            if let total = accountUsage.totalWindow {
                menu.addItem(disabled("\(total.windowLabel)    \(total.remainingPercent)%    重置：\(resetDateTimeFullLabel(total.resetsAt))"))
                menu.addItem(disabled("\(total.windowLabel)已用：\(total.usedPercent)%"))
            }
            menu.addItem(disabled("计划：\(accountUsage.planLabel)"))
            if let resetCredits = accountUsage.resetCredits {
                menu.addItem(disabled("完整重置：\(resetCredits.availableCount) 次可用"))
                for (index, expiration) in resetCredits.expirations.prefix(3).enumerated() {
                    menu.addItem(disabled("重置券 \(index + 1) 过期：\(resetDateTimeLabel(expiration))"))
                }
            }
            if let accountError = snapshot.accountError {
                menu.addItem(disabled("状态：\(accountError)"))
            }
            menu.addItem(disabled("成功更新：\(timeFormatter.string(from: accountUsage.lastSuccessAt))"))
            menu.addItem(disabled("下次刷新：\(timeFormatter.string(from: snapshot.nextRefreshAt))"))
        } else {
            menu.addItem(disabled("剩余用量：读取中"))
            if let error = snapshot.accountError {
                menu.addItem(disabled(error))
            }
        }

        menu.addItem(.separator())

        let threadUsage = snapshot.threadUsage
        if let error = threadUsage.error {
            menu.addItem(disabled("读取失败：\(error)"))
        } else if let current = threadUsage.current {
            let percent = reader.contextRemainingPercent(for: current) ?? 0
            menu.addItem(disabled("当前任务剩余上下文：\(percent)%"))
            menu.addItem(disabled("当前任务已用：\(formatTokens(current.tokens)) tokens"))
            menu.addItem(disabled("模型：\(current.model)"))
            menu.addItem(disabled("任务：\(shorten(current.title, max: 42))"))
        } else {
            menu.addItem(disabled("没有找到 Codex 任务记录"))
        }

        menu.addItem(.separator())
        menu.addItem(disabled("最近 8 个任务合计：\(formatTokens(threadUsage.totalRecentTokens)) tokens"))
        menu.addItem(disabled("更新：\(timeFormatter.string(from: snapshot.checkedAt))"))

        if !threadUsage.recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("最近任务"))
            for thread in threadUsage.recent.prefix(5) {
                menu.addItem(disabled("\(formatTokens(thread.tokens))  \(shorten(thread.title, max: 36))"))
            }
        }

        let rootMenu = NSMenu()
        rootMenu.appearance = NSAppearance(named: .darkAqua)
        rootMenu.addItem(disabled("码伴 · Mac"))
        menu.appearance = NSAppearance(named: .darkAqua)
        let overview = NSMenuItem()
        overview.view = QuotaDashboardView(snapshot: snapshot, balance: deepSeekBalance, error: deepSeekError, date: deepSeekUpdatedAt)
        rootMenu.addItem(overview)
        let details = NSMenuItem(title: "用量与任务详情", action: nil, keyEquivalent: "")
        details.submenu = menu
        rootMenu.addItem(details)
        #if WIDGET_SUPPORT
        let widgetHelp = NSMenuItem(title: "添加 macOS 小组件…", action: #selector(showWidgetHelp), keyEquivalent: "")
        widgetHelp.target = self
        rootMenu.addItem(widgetHelp)
        if let widgetError { rootMenu.addItem(disabled(widgetError)) }
        #endif
        let about = NSMenuItem(title: "关于码伴 Mac…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        rootMenu.addItem(about)
        let mobileHelp = NSMenuItem(title: "手机与手表连接说明…", action: #selector(showMobileHelp), keyEquivalent: "")
        mobileHelp.target = self
        rootMenu.addItem(mobileHelp)
        rootMenu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        rootMenu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        rootMenu.addItem(quitItem)

        statusItem.menu = rootMenu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        refresh()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "codexusagebar" && $0.host == "refresh" }) else { return }
        refresh()
        statusItem.button?.performClick(nil)
    }

    @objc private func showWidgetHelp() {
        let alert = NSAlert()
        alert.messageText = "添加码伴余额小组件"
        alert.informativeText = "在桌面右键选择‘编辑小组件’，搜索‘码伴’，选择小号、中号或大号并添加。\n\n菜单栏应用运行时每 60 秒同步数据；小组件的实际刷新由 macOS 调度。点击小组件可打开本应用并请求同步。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "码伴 · CodeCompanion Mac"
        alert.informativeText = "菜单栏与桌面小组件显示 Codex 额度、DeepSeek 余额和可用重置券。Mac 可独立使用；iPhone 与 Apple Watch 为可选扩展。\n\n余额查询不会调用付费生成模型。DeepSeek 优先复用码伴本地密钥配置。桌面摘要不等于手机服务已部署，连接手机仍需按说明配置。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func showMobileHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/keeencra/codex-quota-watch-plus/blob/main/docs/setup.md")!)
    }

    @objc private func manualRefresh() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func shorten(_ value: String, max: Int) -> String {
        guard value.count > max else { return value }
        let end = value.index(value.startIndex, offsetBy: max)
        return String(value[..<end]) + "..."
    }

    private func resetDateLabel(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func resetDateTimeFullLabel(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm:ss"
        return formatter.string(from: date)
    }

    private func resetDateTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm:ss"
        return formatter.string(from: date)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    private func clockLabelWithSeconds(_ date: Date?) -> String {
        guard let date else { return "--:--:--" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

let app = NSApplication.shared
#if WIDGET_SUPPORT
if CommandLine.arguments.contains("--widget-status") {
    WidgetCenter.shared.getCurrentConfigurations { result in
        switch result {
        case .success(let widgets):
            print("Configured Codex widgets: \(widgets.filter { $0.kind == WidgetSnapshotStore.kind }.count)")
        case .failure(let error): print("Widget configuration query failed: \(error)")
        }
        exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { exit(1) }
    app.run()
}
#endif
let delegate = AppDelegate()
app.delegate = delegate
app.run()
