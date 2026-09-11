import XCTest
@testable import QuotaShared

final class TaskDashboardTests: XCTestCase {
    func testCountsSeparateRunningWaitingAndStaleTasks() throws {
        let tasks = [
            task("a", "running"), task("b", "needs_approval"),
            task("c", "running", stale: true), task("d", "finished"), task("e", "stalled")
        ]
        let snapshot = TaskDashboardSnapshot(updatedAt: "now", tasks: tasks)
        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertEqual(snapshot.attentionCount, 3)
        XCTAssertEqual(tasks[2].statusLabel, "状态待确认")
        XCTAssertEqual(tasks[0].displayTitle, "Project")
    }
    func testPayloadWithNullableTitleAndFractionalTimestamp() throws {
        let json = #"{"updated_at":"2026-09-11T16:00:00.123+00:00","tasks":[{"id":"t","title":null,"project":"Demo","status":"running","phase":"正在执行工具","updated_at":"now","started_at":"then","stale":false,"recent":[{"text":"开始处理","at":"now"}]}]}"#
        let snapshot = try JSONDecoder().decode(TaskDashboardSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.tasks[0].displayTitle, "Demo")
        XCTAssertEqual(snapshot.tasks[0].recent.count, 1)
        XCTAssertNotEqual(TaskTime.label(snapshot.updatedAt), "时间未知")
        XCTAssertEqual(TaskTime.label("invalid"), "时间未知")
        XCTAssertNotNil(ApprovalClient.endpoint(base: "https://example.com", path: "/tasks"))
        XCTAssertNil(ApprovalClient.endpoint(base: "https://example.com", path: "/tasks/other"))
    }
    private func task(_ id: String, _ status: String, stale: Bool = false) -> DashboardTask {
        DashboardTask(id: id, project: "Project", title: nil, status: status, phase: "phase", updatedAt: "now", startedAt: "then", stale: stale, recent: [])
    }
}
