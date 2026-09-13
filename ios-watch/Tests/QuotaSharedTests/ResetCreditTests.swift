import XCTest
@testable import QuotaShared

final class ResetCreditTests: XCTestCase {
    func testOldSnapshotAndNewCreditMetadata() throws {
        let original = WatchSnapshot.placeholder
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "reset_credits")
        XCTAssertNil(try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: object)).resetCredits)
        object["reset_credits"] = ["available_count": 1, "expirations": [2000.0]]
        let new = try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(new.resetCredits?.availableCount, 1)
        XCTAssertEqual(new.resetCredits?.expirations, [2000])
        XCTAssertEqual(try JSONDecoder().decode(WatchSnapshot.self, from: JSONEncoder().encode(new)), new)
    }
    func testResetTimestampRemainsOptional() throws {
        let data = Data(#"{"window":"7d","remaining_percent":32,"reset_at_epoch":2000}"#.utf8)
        let bucket = try JSONDecoder().decode(QuotaBucket.self, from: data)
        XCTAssertEqual(bucket.resetAt, 2000)
        let legacy = try JSONDecoder().decode(QuotaBucket.self, from: Data(#"{"window":"7d"}"#.utf8))
        XCTAssertNil(legacy.resetAt)
    }
}
