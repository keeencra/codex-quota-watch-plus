import XCTest
@testable import QuotaShared

final class WatchComplicationTests: XCTestCase {
    func testUnpairedDoesNotInventFullOrZeroBalance() {
        let value = WatchComplicationSummary(snapshot: nil)
        XCTAssertNil(value.progress)
        XCTAssertEqual(value.quota, "Codex 等待同步")
        XCTAssertEqual(value.balance, "")
        XCTAssertFalse(value.showsDeepSeek)
        XCTAssertFalse(value.cached)
    }

    func testResetUsesSuppliedQuotaAndKeepsUnknownUnknown() {
        var snapshot = WatchSnapshot.placeholder
        snapshot.codex.status = "ok"
        snapshot.codex.buckets = nil
        snapshot.codex.remainingPercent = 93
        XCTAssertEqual(WatchComplicationSummary(snapshot: snapshot).progress, 0.93)
        snapshot.codex.remainingPercent = 100
        XCTAssertEqual(WatchComplicationSummary(snapshot: snapshot).progress, 1)
        snapshot.codex.remainingPercent = nil
        XCTAssertNil(WatchComplicationSummary(snapshot: snapshot).progress)
    }

    func testResetDateMatchesWeeklyBarAndUsesGregorianLocalTime() throws {
        var snapshot = WatchSnapshot.placeholder
        snapshot.codex.status = "ok"
        snapshot.codex.buckets = try JSONDecoder().decode([QuotaBucket].self, from: Data("""
        [{"id":"codex:5h","window":"5h","remaining_percent":25,"reset_at_epoch":1792296000},
         {"id":"codex:7d","window":"7d","remaining_percent":93,"reset_at_epoch":1792382400}]
        """.utf8))
        let now = Date(timeIntervalSince1970: 1792200000)
        let value = WatchComplicationSummary(snapshot: snapshot, now: now, timeZone: TimeZone(secondsFromGMT: 28800)!)
        XCTAssertEqual(value.progress, 0.93)
        XCTAssertEqual(value.percent, "93%")
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = TimeZone(secondsFromGMT: 28800)!
        format.dateFormat = "MM/dd HH:mm"
        XCTAssertEqual(value.resetLabel, "Codex " + format.string(from: Date(timeIntervalSince1970: 1792382400)) + " 重置")
        let expired = WatchComplicationSummary(snapshot: snapshot, now: Date(timeIntervalSince1970: 1792382401))
        XCTAssertEqual(expired.resetLabel, "Codex 重置待刷新")
        XCTAssertEqual(expired.percent, "93%")
        XCTAssertEqual(WatchComplicationSummary(snapshot: nil).resetLabel, "Codex 重置时间 --")
    }

    func testBalancesKeepCurrencyAndZero() throws {
        var snapshot = WatchSnapshot.placeholder
        snapshot.updatedAt = "2026-10-18T03:00:00Z"
        snapshot.deepseek = try JSONDecoder().decode(DeepSeekBalance.self, from: Data("""
        {"status":"ok","balance_infos":[{"currency":"CNY","total_balance":"0.00","granted_balance":"0","topped_up_balance":"0"},{"currency":"USD","total_balance":"20.50","granted_balance":"0","topped_up_balance":"20.50"}]}
        """.utf8))
        let value = WatchComplicationSummary(snapshot: snapshot)
        XCTAssertEqual(value.balance, "DeepSeek ¥0 / $20.5")
    }

    func testOldOrFailedSnapshotsMarkedCachedWithoutChangingQuota() {
        var snapshot = WatchSnapshot.placeholder
        snapshot.codex.status = "ok"
        snapshot.updatedAt = "2026-10-18T03:00:00.000Z"
        let now = ISO8601DateFormatter().date(from: "2026-10-18T03:00:00Z")!
        let fresh = WatchComplicationSummary(snapshot: snapshot, now: now)
        let old = WatchComplicationSummary(snapshot: snapshot, now: now.addingTimeInterval(900))
        let failed = WatchComplicationSummary(snapshot: snapshot, failed: true, now: now)
        XCTAssertFalse(fresh.cached)
        XCTAssertTrue(old.cached)
        XCTAssertTrue(failed.cached)
        XCTAssertEqual(old.progress, fresh.progress)
        XCTAssertEqual(failed.quota, fresh.quota)
    }
}
