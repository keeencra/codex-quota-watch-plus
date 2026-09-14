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
    var dailyTokens: DailyTokenUsage = .empty()
}


// Local records only: neither provider's account-wide billing history is inferred.
struct DailyTokenUsage {
    struct Day {
        let date: Date
        var codex: Int = 0
        var deepSeek: Int = 0
    }
    var days: [Day]
    var codexStatus: String?
    var deepSeekStatus: String?
    static func calendar(_ zone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar
    }
    static func empty(now: Date = Date(), zone: TimeZone = .current) -> DailyTokenUsage {
        let calendar = calendar(zone), today = calendar.startOfDay(for: now)
        return DailyTokenUsage(days: (-6...0).map { Day(date: calendar.date(byAdding: .day, value: $0, to: today)!) },
                               codexStatus: "读取中", deepSeekStatus: "读取中")
    }
    static func number(_ count: Int) -> String {
        if count >= 1_000_000_000 { return String(format: "%.2fB", Double(count) / 1_000_000_000) }
        if count >= 1_000_000 { return String(format: "%.2fM", Double(count) / 1_000_000) }
        if count >= 1000 { return String(format: "%.1fK", Double(count) / 1000) }
        return String(count)
    }
}

final class DailyTokenReader {
    struct Event { let date: Date; let tokens: Int }
    private struct Cached { let modified: Date; let size: Int; let inode: UInt64; let offset: UInt64; let previous: (Int, Int)?; let events: [String: Event] }
    private var cache: [String: Cached] = [:]
    private let lock = NSLock()
    private let home: URL
    init(home: URL = URL(fileURLWithPath: NSHomeDirectory())) { self.home = home }
    private static let fractionalDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeDate = ISO8601DateFormatter()
    static func date(_ value: String) -> Date? {
        fractionalDate.date(from: value) ?? wholeDate.date(from: value)
    }
    // Input already includes cached input; reasoning output is already in output.
    static func counts(_ value: Any?) -> (Int, Int)? {
        guard let dict = value as? [String: Any], let input = dict["input_tokens"] as? Int,
              let output = dict["output_tokens"] as? Int, input >= 0, output >= 0,
              input <= Int.max - output else { return nil }
        return (input, output)
    }
    static func consume(_ line: Data, previous: inout (Int, Int)?, events: inout [String: Event]) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any], let total = counts(info["total_token_usage"]) else { return }
        let old = previous
        previous = total
        let delta: (Int, Int)?
        if let old, total.0 >= old.0, total.1 >= old.1 { delta = (total.0 - old.0, total.1 - old.1) }
        else { delta = counts(info["last_token_usage"]) }
        guard let delta, delta.0 + delta.1 > 0,
              let stamp = object["timestamp"] as? String, let date = date(stamp) else { return }
        // The same recorded event may appear in both sessions and archived copies.
        let key = "\(stamp)|\(total.0)|\(total.1)"
        events[key] = Event(date: date, tokens: delta.0 + delta.1)
    }
    private func scan(_ path: URL, resume: Cached? = nil) throws -> (UInt64, (Int, Int)?, [String: Event]) {
        let handle = try FileHandle(forReadingFrom: path); defer { try? handle.close() }
        var buffer = Data(), previous = resume?.previous, events = resume?.events ?? [:]
        var offset = resume?.offset ?? 0
        try handle.seek(toOffset: offset)
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            var start = buffer.startIndex
            while let end = buffer[start...].firstIndex(of: 10) {
                let line = buffer[start..<end]
                if line.range(of: Data("token_count".utf8)) != nil { Self.consume(Data(line), previous: &previous, events: &events) }
                start = end + 1
            }
            offset += UInt64(start)
            buffer = Data(buffer[start...])
        }
        // An unterminated live write is retried when the file changes.
        return (offset, previous, events)
    }
    func read(now: Date = Date(), zone: TimeZone = .current) -> DailyTokenUsage {
        lock.lock(); defer { lock.unlock() }
        var result = DailyTokenUsage.empty(now: now, zone: zone)
        let calendar = DailyTokenUsage.calendar(zone), start = result.days[0].date
        var events: [String: Event] = [:], paths = Set<String>(), rootsFound = false, failure = false
        for name in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(".codex/" + name)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            rootsFound = true
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], errorHandler: { _, _ in failure = true; return true }) else { failure = true; continue }
            for case let path as URL in files where path.pathExtension == "jsonl" {
                do {
                    let values = try path.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let modified = values.contentModificationDate ?? .distantPast, size = values.fileSize ?? 0
                    guard modified >= start else { continue }
                    paths.insert(path.path)
                    if cache[path.path]?.modified != modified || cache[path.path]?.size != size {
                        let inode = (try FileManager.default.attributesOfItem(atPath: path.path)[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                        let old = cache[path.path]
                        let resume = old != nil && inode != 0 && old!.inode == inode && size > old!.size ? old : nil
                        let scanned = try scan(path, resume: resume)
                        cache[path.path] = Cached(modified: modified, size: size, inode: inode, offset: scanned.0, previous: scanned.1, events: scanned.2)
                    }
                    for (key, event) in cache[path.path]?.events ?? [:] where event.date >= start && event.date <= now { events[key] = event }
                } catch { failure = true }
            }
        }
        cache = cache.filter { paths.contains($0.key) }
        for event in events.values {
            if let index = result.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: event.date) }) { result.days[index].codex += event.tokens }
        }
        result.codexStatus = failure ? "部分记录未读到" : (rootsFound ? nil : "未找到会话记录")
        let database = home.appendingPathComponent(".codex/tools/deepseek/state/usage.sqlite3")
        guard FileManager.default.fileExists(atPath: database.path) else { result.deepSeekStatus = "未找到本机记录"; return result }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path,
            "select started,total_tokens,prompt_tokens,completion_tokens from calls where julianday(started)>=julianday(\(start.timeIntervalSince1970),'unixepoch') and julianday(started)<=julianday(\(now.timeIntervalSince1970),'unixepoch');"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { result.deepSeekStatus = "本机记录读取失败"; return result }
            let rows = data.isEmpty ? [] : (try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? [])
            var incomplete = false
            for row in rows {
                guard let stamp = row["started"] as? String, let date = Self.date(stamp),
                      let index = result.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { incomplete = true; continue }
                let total = row["total_tokens"] as? Int ?? {
                    guard let input = row["prompt_tokens"] as? Int, let output = row["completion_tokens"] as? Int, input >= 0, output >= 0, input <= Int.max - output else { return nil as Int? }
                    return input + output
                }()
                if let total, total >= 0 { result.days[index].deepSeek += total } else { incomplete = true }
            }
            result.deepSeekStatus = incomplete ? "部分调用缺少用量" : nil
        } catch { result.deepSeekStatus = "本机记录读取失败" }
        return result
    }
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

// Display quota timestamps in the Gregorian calendar, regardless of system calendar.
enum QuotaTimestamp {
    static func label(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "待更新" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
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

    // Show every funded currency independently; never convert or add currencies.
    var menuBarAmount: String {
        let positive = balance_infos.filter { (Decimal(string: $0.total_balance) ?? 0) > 0 }
        let entries = positive.isEmpty ? balance_infos : positive
        let ordered = entries.sorted {
            func rank(_ currency: String) -> Int { currency == "CNY" ? 0 : (currency == "USD" ? 1 : 2) }
            let left = rank($0.currency), right = rank($1.currency)
            return left == right ? $0.currency < $1.currency : left < right
        }
        return ordered.isEmpty ? "—" : ordered.map { $0.display }.joined(separator: " / ")
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
    let widgetError: String?
    private let ink = NSColor(calibratedWhite: 0.94, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.54, green: 0.60, blue: 0.69, alpha: 1)
    private let purple = NSColor(calibratedRed: 0.63, green: 0.57, blue: 1, alpha: 1)
    private let teal = NSColor(calibratedRed: 0.35, green: 0.83, blue: 0.79, alpha: 1)
    override var isFlipped: Bool { true }
    init(snapshot: AppSnapshot, balance: DeepSeekBalance?, error: String?, date: Date?, widgetError: String? = nil) {
        self.snapshot = snapshot; self.balance = balance; balanceError = error; balanceDate = date; self.widgetError = widgetError
        super.init(frame: NSRect(x: 0, y: 0, width: 368, height: 0))
        setFrameSize(NSSize(width: 368, height: contentHeight))
        setAccessibilityElement(true)
        setAccessibilityLabel("AI 额度与用量。向下滚动查看每日精确用量、账户详情和任务记录。" + detailSections.map { $0.0 + "。" + $0.1.map { $0.0 + "：" + $0.1 }.joined(separator: "。") }.joined(separator: "。"))
    }
    required init?(coder: NSCoder) { fatalError() }
    private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat = 310, size: CGFloat = 12,
                      color: NSColor? = nil, weight: NSFont.Weight = .regular, mono: Bool = false, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = alignment
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
        QuotaTimestamp.label(date)
    }
    var overviewHeight: CGFloat { CGFloat(538 + max(1, snapshot.accountUsage?.windows.count ?? 0) * 42) }
    private var detailSections: [(String, [(String, String)])] {
        var account: [(String, String)] = []
        if let usage = snapshot.accountUsage {
            account.append(("Codex · " + usage.planLabel, "成功更新 " + stamp(usage.lastSuccessAt)))
            for window in usage.windows {
                account.append((window.windowLabel + " · 已用 \(window.usedPercent)% / 剩余 \(window.remainingPercent)%", "重置 " + stamp(window.resetsAt)))
            }
            if let credits = usage.resetCredits {
                account.append(("重置卡", "\(credits.availableCount) 张可用"))
                for (index, expiry) in credits.expirations.enumerated() { account.append(("卡 \(index + 1) · 到期", stamp(expiry))) }
            }
        }
        if let error = snapshot.accountError { account.append(("Codex 状态", error)) }
        account.append(("下次额度刷新", stamp(snapshot.nextRefreshAt)))
        if let widgetError { account.append(("小组件同步状态", widgetError)) }
        if let balance {
            account.append(("DeepSeek", balance.is_available ? "账户可用 · 更新 " + stamp(balanceDate) : "余额不足"))
            for entry in balance.balance_infos {
                account.append((entry.currency + " · 总余额 " + entry.total_balance, "充值 " + entry.topped_up_balance + " · 赠送 " + entry.granted_balance))
            }
        } else { account.append(("DeepSeek 状态", balanceError ?? "正在查询")) }
        var tasks: [(String, String)] = []
        let usage = snapshot.threadUsage
        tasks.append(("最近 \(usage.recent.count) 个任务 · 累计 token", "\(usage.totalRecentTokens) · 属于任务累计值，不是今日消耗"))
        if let error = usage.error { tasks.append(("读取失败", error)) }
        else if let current = usage.current {
            let context = CodexUsageReader().contextRemainingPercent(for: current)
            tasks.append(("最近更新任务", current.title))
            tasks.append(("上下文剩余（本地估算）", context.map { "\($0)% · 模型 " + current.model } ?? "未知"))
        }
        for thread in usage.recent {
            tasks.append((thread.title, "\(thread.tokens) tokens · \(thread.model)\n更新 " + stamp(Date(timeIntervalSince1970: Double(thread.updatedAtMs) / 1000))))
        }
        if usage.recent.isEmpty && usage.error == nil { tasks.append(("暂无任务", "没有找到本地 Codex 任务记录")) }
        return [("账户与重置卡详情", account), ("用量与任务详情", tasks)]
    }
    private func wrappedHeight(_ value: String, size: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        let bounds = (value as NSString).boundingRect(with: NSSize(width: 310, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph])
        return max(size + 5, ceil(bounds.height) + 3)
    }
    private func sectionHeight(_ rows: [(String, String)]) -> CGFloat {
        43 + rows.reduce(CGFloat(0)) { $0 + wrappedHeight($1.0, size: 11) + wrappedHeight($1.1, size: 10) + 14 }
    }
    var anchors: [CGFloat] {
        [0, overviewHeight, overviewHeight + 236, overviewHeight + 244 + sectionHeight(detailSections[0].1)]
    }
    var contentHeight: CGFloat { anchors[3] + sectionHeight(detailSections[1].1) + 16 }
    private func wrapped(_ value: String, y: CGFloat, size: CGFloat, color: NSColor) -> CGFloat {
        let height = wrappedHeight(value, size: size)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: NSRect(x: 28, y: y, width: 310, height: height), withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph])
        return height
    }
    private func drawDetails() {
        var y = overviewHeight
        card(y: y, height: 228)
        text("每日 token · 精确数值", x: 28, y: y + 12, size: 13, weight: .semibold)
        text("日期", x: 28, y: y + 40, width: 58, size: 10, color: muted)
        text("Codex", x: 98, y: y + 40, width: 111, size: 11, color: purple, alignment: .right)
        text("DeepSeek", x: 220, y: y + 40, width: 118, size: 11, color: teal, alignment: .right)
        for (index, day) in snapshot.dailyTokens.days.enumerated() {
            let row = y + 61 + CGFloat(index) * 20
            text(index == 6 ? "今天" : String(QuotaTimestamp.label(day.date).prefix(5)), x: 28, y: row, width: 58, size: 10, color: muted)
            text(snapshot.dailyTokens.codexStatus == nil || day.codex > 0 ? String(day.codex) : "—", x: 89, y: row, width: 120, size: 10, mono: true, alignment: .right)
            text(snapshot.dailyTokens.deepSeekStatus == nil || day.deepSeek > 0 ? String(day.deepSeek) : "—", x: 215, y: row, width: 123, size: 10, mono: true, alignment: .right)
        }
        text("本机记录 · 含缓存输入 · 非账户全量账单", x: 28, y: y + 205, size: 9, color: muted)
        y += 236
        for (title, rows) in detailSections {
            let height = sectionHeight(rows)
            card(y: y, height: height)
            text(title, x: 28, y: y + 12, size: 13, weight: .semibold)
            var row = y + 39
            for (label, value) in rows {
                row += wrapped(label, y: row, size: 11, color: ink)
                row += wrapped(value, y: row, size: 10, color: muted) + 14
            }
            y += height + 8
        }
    }
    private func tokenChart(y: CGFloat, title: String, values: [Int], status: String?, scope: String, tint: NSColor) {
        card(y: y, height: 137)
        text(title, x: 28, y: y + 10, width: 138, size: 13, color: tint, weight: .semibold)
        let total = values.reduce(0, +)
        let totalLabel = status == nil || total > 0 ? DailyTokenUsage.number(total) : "—"
        text("7 天合计 " + totalLabel, x: 180, y: y + 12, width: 158, size: 10, mono: true, alignment: .right)
        let peak = values.max() ?? 0
        text(status ?? scope, x: 28, y: y + 30, width: 193, size: 9, color: muted)
        text(peak > 0 ? "0–" + DailyTokenUsage.number(peak) + " · 独立刻度" : (status == nil ? "无已记录用量" : "暂无刻度"), x: 215, y: y + 30, width: 124, size: 8, color: muted, alignment: .right)
        let base = y + 110, chartHeight: CGFloat = 51
        for fraction in [CGFloat(0), 0.5, 1] {
            NSColor.white.withAlphaComponent(0.07).setFill()
            NSRect(x: 28, y: base - chartHeight * fraction, width: 310, height: 0.5).fill()
        }
        let dates = DateFormatter(); dates.locale = Locale(identifier: "en_US_POSIX")
        dates.calendar = DailyTokenUsage.calendar(); dates.timeZone = .current; dates.dateFormat = "MM/dd"
        let days = snapshot.dailyTokens.days
        let step: CGFloat = 310 / CGFloat(max(1, days.count))
        for (index, day) in days.enumerated() {
            let value = values[index], x = 28 + CGFloat(index) * step
            let today = index == days.count - 1
            let height = peak > 0 ? chartHeight * CGFloat(value) / CGFloat(peak) : 0
            if today {
                tint.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 1, y: y + 48, width: step - 2, height: 82), xRadius: 5, yRadius: 5).fill()
            }
            if value > 0 {
                tint.withAlphaComponent(today ? 1 : 0.70).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + (step - 21) / 2, y: base - height, width: 21, height: height), xRadius: min(3, height / 2), yRadius: min(3, height / 2)).fill()
            }
            let label = status == nil || value > 0 ? DailyTokenUsage.number(value) : "—"
            text(label, x: x, y: base - height - 13, width: step, size: 8, color: today ? ink : muted, mono: true, alignment: .center)
            text(today ? "今天" : dates.string(from: day.date), x: x, y: base + 5, width: step, size: 9, color: today ? tint : muted, alignment: .center)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.052, blue: 0.083, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 14, yRadius: 14).fill()
        text("AI 额度与用量", x: 24, y: 13, size: 17, weight: .bold)
        text("每 60 秒刷新", x: 248, y: 18, width: 96, size: 9, color: muted, alignment: .right)
        var y: CGFloat = 45
        let windows = snapshot.accountUsage?.windows ?? []
        let ch = CGFloat(58 + max(1, windows.count) * 42)
        card(y: y, height: ch)
        text("Codex", x: 28, y: y + 10, size: 14, weight: .semibold)
        let plan = snapshot.accountUsage?.planType == "prolite" ? "Pro" : (snapshot.accountUsage?.planLabel ?? "—")
        text(plan, x: 251, y: y + 12, width: 87, size: 11, color: purple, weight: .semibold, alignment: .right)
        var row = y + 34
        if windows.isEmpty { text("额度暂不可用", x: 28, y: row, color: muted) }
        for window in windows {
            let label = window.windowLabel == "1周" ? "周额度" : (window.windowLabel == "5小时" ? "5h 额度" : window.windowLabel)
            text(label, x: 28, y: row, width: 90, size: 10, color: muted)
            text("\(window.remainingPercent)%", x: 258, y: row - 4, width: 80, size: 19, weight: .semibold, mono: true, alignment: .right)
            text("重置 " + stamp(window.resetsAt), x: 28, y: row + 16, width: 230, size: 9, color: muted)
            let tint = window.remainingPercent <= 10 ? NSColor.systemRed : (window.remainingPercent <= 50 ? NSColor.systemOrange : purple)
            let track = NSRect(x: 28, y: row + 32, width: 310, height: 4)
            tint.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
            let progress = max(0, min(1, CGFloat(window.remainingPercent) / 100))
            if progress > 0 {
                tint.setFill()
                NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: 4), xRadius: 2, yRadius: 2).fill()
            }
            row += 42
        }
        text(snapshot.accountError == nil ? "已更新 " + stamp(snapshot.accountUsage?.lastSuccessAt) : "缓存数据 · 暂未连接", x: 28, y: y + ch - 16, size: 8, color: muted)
        y += ch + 8
        card(y: y, height: 86)
        text("DeepSeek 余额", x: 28, y: y + 10, size: 13, weight: .semibold)
        text(balance == nil ? "未连接" : (balance!.is_available ? "官方 API" : "余额不足"), x: 253, y: y + 12, width: 85, size: 9, color: balance?.is_available == false ? .systemOrange : teal, alignment: .right)
        if let balance, !balance.balance_infos.isEmpty {
            // Show balances side-by-side. Detailed credit breakdown stays in the submenu.
            let entries = balance.balance_infos.sorted { $0.currency < $1.currency }
            for (index, entry) in entries.prefix(2).enumerated() {
                let x: CGFloat = index == 0 ? 28 : 195
                text(entry.currency, x: x, y: y + 31, width: 143, size: 9, color: muted)
                text(entry.display, x: x, y: y + 44, width: 143, size: 20, weight: .semibold, mono: true)
            }
        } else { text(balanceError ?? "正在查询余额", x: 28, y: y + 40, size: 11, color: muted) }
        text("更新 " + stamp(balanceDate), x: 28, y: y + 70, size: 8, color: muted)
        y += 94
        text("近 7 天 · 每日 tokens", x: 24, y: y + 1, size: 12, weight: .semibold)
        text("含今天 · 本地公历日", x: 217, y: y + 3, width: 127, size: 9, color: muted, alignment: .right)
        y += 25
        let daily = snapshot.dailyTokens
        tokenChart(y: y, title: "Codex", values: daily.days.map(\.codex), status: daily.codexStatus, scope: "本机会话 · 含缓存输入", tint: purple)
        y += 145
        tokenChart(y: y, title: "DeepSeek", values: daily.days.map(\.deepSeek), status: daily.deepSeekStatus, scope: "本机工具 · 不含其他软件", tint: teal)
        text("0 无已记录用量 · — 记录不可用 · 向下滚动查看精确明细", x: 24, y: y + 145, width: 324, size: 8, color: muted)
        drawDetails()
    }

}

final class QuotaPanelController: NSViewController {
    private let scroll = NSScrollView()
    private var dashboard: QuotaDashboardView?
    private var callbacks: [() -> Void] = []
    var panelHeight: CGFloat = 720
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: panelHeight))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.052, blue: 0.083, alpha: 1).cgColor
        view.appearance = NSAppearance(named: .darkAqua)
        scroll.frame = NSRect(x: 0, y: 63, width: 368, height: panelHeight - 101)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        view.addSubview(scroll)
        for (index, title) in ["总览", "每日明细", "账户详情", "任务"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(jump(_:)))
            button.tag = index; styleButton(button, size: 11)
            button.frame = NSRect(x: 16 + CGFloat(index) * 86, y: panelHeight - 32, width: 80, height: 24)
            view.addSubview(button)
        }
    }
    private func styleButton(_ button: NSButton, size: CGFloat) {
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1)])
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.09, blue: 0.135, alpha: 1).cgColor
    }
    func setActions(_ actions: [(String, () -> Void)]) {
        _ = view
        callbacks = actions.map(\.1)
        for (index, item) in actions.enumerated() {
            let button = NSButton(title: item.0, target: self, action: #selector(performAction(_:)))
            button.tag = index; styleButton(button, size: 10)
            button.frame = NSRect(x: 16 + CGFloat(index % 3) * 113, y: index < 3 ? 32 : 7, width: 105, height: 22)
            view.addSubview(button)
        }
    }
    func update(_ dashboard: QuotaDashboardView) {
        _ = view
        let offset = scroll.contentView.bounds.origin.y
        self.dashboard = dashboard
        scroll.documentView = dashboard
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset, max(0, dashboard.frame.height - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func scrollToTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func jump(_ sender: NSButton) {
        guard let dashboard else { return }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(dashboard.anchors[sender.tag], max(0, dashboard.frame.height - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func performAction(_ sender: NSButton) { callbacks[sender.tag]() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var panelController: QuotaPanelController?
    private let accountReader = AccountUsageReader()
    private let reader = CodexUsageReader()
    private let dailyReader = DailyTokenReader()
    private var dailyLoading = false
    private var latestDailyTokens = DailyTokenUsage.empty()
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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        if !dailyLoading {
            dailyLoading = true
            DispatchQueue.global(qos: .utility).async {
                let daily = self.dailyReader.read()
                DispatchQueue.main.async {
                    self.dailyLoading = false
                    self.latestDailyTokens = daily
                    if var snapshot = self.latestSnapshot {
                        snapshot.dailyTokens = daily
                        self.latestSnapshot = snapshot
                        self.updatePanel(snapshot)
                    }
                }
            }
        }
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
                        self.updatePanel(snapshot)
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
                var snapshot = snapshot
                snapshot.dailyTokens = self.latestDailyTokens
                self.latestSnapshot = snapshot
                self.updateTitle(snapshot)
                self.updatePanel(snapshot)
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

    private func updatePanel(_ snapshot: AppSnapshot) {
        if panelController == nil {
            let controller = QuotaPanelController()
            let available = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
            controller.panelHeight = min(760, max(340, available - 60))
            controller.setActions([
                ("刷新", { [weak self] in self?.manualRefresh() }),
                ("添加小组件", { [weak self] in self?.popover.performClose(nil); self?.showWidgetHelp() }),
                ("手机与手表", { [weak self] in self?.popover.performClose(nil); self?.showMobileHelp() }),
                ("关于码伴", { [weak self] in self?.popover.performClose(nil); self?.showAbout() }),
                ("回到顶部", { [weak self] in self?.panelController?.scrollToTop() }),
                ("退出", { [weak self] in self?.quit() })
            ])
            panelController = controller
            popover.behavior = .transient
            popover.contentViewController = controller
            popover.contentSize = controller.view.frame.size
            popover.appearance = NSAppearance(named: .darkAqua)
        }
        panelController?.update(QuotaDashboardView(snapshot: snapshot, balance: deepSeekBalance, error: deepSeekError, date: deepSeekUpdatedAt, widgetError: widgetError))
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        if panelController == nil {
            let now = Date()
            updatePanel(AppSnapshot(accountUsage: nil, threadUsage: UsageSnapshot(current: nil, recent: [], totalRecentTokens: 0, checkedAt: now, error: nil), checkedAt: now, nextRefreshAt: now, accountError: "正在读取"))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        refresh()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "codexusagebar" && $0.host == "refresh" }) else { return }
        refresh()
        if !popover.isShown { togglePanel() }
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

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
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
