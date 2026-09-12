import XCTest
@testable import QuotaShared

final class DeepSeekTests: XCTestCase {
    func testWidgetLayoutFollowsConfigurationIncludingZeroBalanceAndFailures() throws {
        var snapshot = WatchSnapshot.placeholder
        snapshot.deepseek = nil
        XCTAssertFalse(snapshot.showsDeepSeekInWidget)
        for (status, expected) in [("not_configured", false), ("ok", true), ("error", true)] {
            snapshot.deepseek = try JSONDecoder().decode(DeepSeekBalance.self, from: Data("""
            {"status":"\(status)","is_available":false,"balance_infos":[
             {"currency":"CNY","total_balance":"0.00","granted_balance":"0","topped_up_balance":"0"}]}
            """.utf8))
            XCTAssertEqual(snapshot.showsDeepSeekInWidget, expected, status)
        }
    }

    func testBalanceSurvivesPhoneWatchAndCacheRoundtrip() throws {
        let balance = try JSONDecoder().decode(DeepSeekBalance.self, from: Data("""
        {"status":"ok","updated_at":"2026-09-13T00:00:00Z","is_available":false,
         "balance_infos":[{"currency":"CNY","total_balance":"0.0000","granted_balance":"0.00","topped_up_balance":"0.00"},
         {"currency":"USD","total_balance":"0.123456","granted_balance":"0.00","topped_up_balance":"0.123456"}]}
        """.utf8))
        var snapshot = WatchSnapshot.placeholder
        snapshot.deepseek = balance
        let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.deepseek, balance)
        XCTAssertEqual(balance.balanceInfos[0].compactTotal, "0")
        XCTAssertEqual(balance.balanceInfos[1].compactTotal, "0.123456")
        XCTAssertEqual(balance.summary, "CNY 0.0000 · USD 0.123456")
        XCTAssertTrue(balance.statusMessage.contains("不足"))
    }
    func testOldSnapshotAndMalformedOptionalBalanceDoNotBreakCodex() throws {
        let raw = try JSONEncoder().encode(WatchSnapshot.placeholder)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        payload.removeValue(forKey: "deepseek")
        var decoded = try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(decoded.deepseek)
        payload["deepseek"] = ["status": "ok", "balance_infos": "invalid"]
        decoded = try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(decoded.deepseek)
        XCTAssertEqual(decoded.codex, WatchSnapshot.placeholder.codex)
    }
    func testErrorAndUnconfiguredAreNotZero() throws {
        for status in ["error", "not_configured"] {
            let balance = try JSONDecoder().decode(DeepSeekBalance.self, from: Data("{\"status\":\"\(status)\",\"balance_infos\":[]}".utf8))
            XCTAssertFalse(balance.summary.contains("0"))
        }
    }
}
