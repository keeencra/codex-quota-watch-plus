import XCTest
@testable import QuotaShared

final class ApprovalTests: XCTestCase {
    func testHTTPSOnlyAndNoCredentialsOrQueryInApprovalEndpoint() {
        for base in ["http://quota.example.com", "https://user:secret@quota.example.com", "file:///tmp/test"] {
            XCTAssertNil(ApprovalClient.endpoint(base: base, path: "/approvals"))
        }
        XCTAssertEqual(ApprovalClient.endpoint(base: "https://quota.example.com/old?token=secret#fragment", path: "/approvals")?.absoluteString,
                       "https://quota.example.com/approvals")
    }
    func testExpiredSubmittedAndConsumedRequestsCannotBeApproved() {
        func request(_ status: String, _ expires: Double = 200) -> RemoteApproval {
            RemoteApproval(id: "id", nonce: "nonce", fingerprint: "sha", project: "demo", tool: "Bash", details: "command", expires: expires, status: status, decision: nil)
        }
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(request("pending").canDecide(at: now))
        XCTAssertFalse(request("pending", 100).canDecide(at: now))
        for status in ["submitted", "consumed", "expired", "cancelled"] {
            XCTAssertFalse(request(status).canDecide(at: now))
        }
    }
}
