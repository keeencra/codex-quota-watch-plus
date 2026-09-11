import XCTest
@testable import QuotaShared

final class TaskEventTests: XCTestCase {
    func testLegacySnapshotStillDecodes() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchSnapshot.placeholder)) as? [String: Any])
        json.removeValue(forKey: "task_events")
        json.removeValue(forKey: "notifications")
        let data = try JSONSerialization.data(withJSONObject: json)
        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        XCTAssertTrue(snapshot.taskEvents.isEmpty)
        XCTAssertNil(snapshot.notifications)
    }

    func testTaskHistoryAndSubscriptionSurvivePhoneWatchRoundTrip() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchSnapshot.placeholder)) as? [String: Any])
        json["task_events"] = [["id": "event-1", "project": "test", "status": "needs_approval", "updated_at": "2026-09-11T10:00:00Z", "started_at": "2026-09-11T09:00:00Z"]]
        json["notifications"] = ["enabled": true, "server": "https://ntfy.sh", "topic": "example", "pending_count": 0]
        let original = try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let received = try JSONDecoder().decode(WatchSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(received, original)
        XCTAssertEqual(received.taskEvents.first?.statusLabel, "需要确认")
        XCTAssertEqual(received.notifications?.topic, "example")
    }
}
