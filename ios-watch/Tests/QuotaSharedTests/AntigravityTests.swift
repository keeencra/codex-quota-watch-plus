import XCTest
@testable import QuotaShared

final class AntigravityTests: XCTestCase {
    func testReadOnlyContractAndExhaustedQuota() throws {
        let json = #"{"schema_version":1,"status":"available","sessions":[{"id":"opaque","observed_at":1000,"state":"idle","needs_confirmation":false,"model":"Example","stale":false,"quotas":[{"name":"weekly","remaining":0,"reset":null}]}],"capabilities":{"approval":false}}"#
        let snapshot = try JSONDecoder().decode(AntigravitySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.sessions[0].quotas[0].percentLabel, "0%")
        XCTAssertEqual(snapshot.sessions[0].stateLabel(at: Date(timeIntervalSince1970: 1001)), "空闲（不代表任务完成）")
        XCTAssertEqual(snapshot.sessions[0].stateLabel(at: Date(timeIntervalSince1970: 1900)), "状态已过期")
        XCTAssertTrue(snapshot.sessions[0].isStale(at: Date(timeIntervalSince1970: 0)))
    }
    func testDemoAndEndpointBoundaries() {
        let date = Date(timeIntervalSince1970: 10000)
        let demo = AntigravitySnapshot.demo(now: date)
        XCTAssertEqual(demo.status, "demo")
        XCTAssertTrue(demo.sessions[1].needsConfirmation)
        XCTAssertTrue(demo.sessions[2].isStale(at: date))
        XCTAssertNotNil(ApprovalClient.endpoint(base: "https://example.com", path: "/antigravity"))
        XCTAssertNil(ApprovalClient.endpoint(base: "http://example.com", path: "/antigravity"))
        XCTAssertNil(ApprovalClient.endpoint(base: "https://example.com", path: "/antigravity/approve"))
    }
}

extension AntigravityTests {
    func testSmallPositiveQuotaAndFractionalReset() {
        let quota = AntigravityQuota(name: "weekly", remaining: 0.001, reset: "2026-10-01T00:00:00.123456+00:00")
        XCTAssertEqual(quota.percentLabel, "<1%")
        XCTAssertNotNil(quota.resetDate)
    }
}
