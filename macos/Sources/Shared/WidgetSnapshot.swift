import Foundation
import os

struct WidgetSnapshot: Codable {
    struct Window: Codable {
        var label: String
        var remaining: Int
        var resetsAt: Date?
    }
    struct Balance: Codable {
        var currency: String
        var amount: String
    }
    struct Credits: Codable {
        var availableCount: Int
        var expirations: [Date]
    }
    var updatedAt: Date
    var codexUpdatedAt: Date?
    var plan: String
    var windows: [Window]
    var balances: [Balance]
    var codexError: String?
    var balanceError: String?
    var resetCredits: Credits? = nil
    var recentTokens: Int? = nil

    static let empty = WidgetSnapshot(updatedAt: .distantPast, plan: "Codex", windows: [], balances: [], codexError: "请先打开菜单栏应用", balanceError: nil)
    static let preview = WidgetSnapshot(updatedAt: Date(), codexUpdatedAt: Date(), plan: "Plus", windows: [.init(label: "5h", remaining: 42, resetsAt: Date().addingTimeInterval(7200)), .init(label: "周", remaining: 73, resetsAt: Date().addingTimeInterval(86400))], balances: [.init(currency: "CNY", amount: "¥88.88"), .init(currency: "USD", amount: "$0.00")], resetCredits: .init(availableCount: 2, expirations: [Date().addingTimeInterval(172800), Date().addingTimeInterval(604800)]))
    func isStale(at date: Date) -> Bool { date.timeIntervalSince(updatedAt) > 300 }
}

enum WidgetSnapshotStore {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "WidgetAppGroup") as? String ?? "group.local.codex.usagebar" }
    static let kind = "CodexUsageWidget"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget-snapshot.json")
    }
    static func read() -> WidgetSnapshot {
        do {
            guard let url else { throw CocoaError(.fileReadNoPermission) }
            let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
            Logger(subsystem: "local.codex.usagebar", category: "widget-data").info("Snapshot loaded: \(snapshot.windows.count) windows, \(snapshot.balances.count) currencies")
            return snapshot
        } catch {
            var result = WidgetSnapshot.empty
            let code = (error as NSError).code
            Logger(subsystem: "local.codex.usagebar", category: "widget-data").error("Snapshot read failed, code: \(code)")
            result.codexError = code == NSFileReadNoSuchFileError ? "请先打开菜单栏应用" : "共享数据读取失败，请更新应用"
            return result
        }
    }
    static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
