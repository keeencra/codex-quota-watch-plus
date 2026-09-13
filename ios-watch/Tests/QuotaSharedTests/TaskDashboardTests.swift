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
        XCTAssertEqual(tasks[0].displayTitle, "未命名任务 · a")
    }
    func testPayloadWithNullableTitleAndFractionalTimestamp() throws {
        let json = #"{"updated_at":"2026-09-11T16:00:00.123+00:00","tasks":[{"id":"t","title":null,"project":"Demo","status":"running","phase":"正在执行工具","updated_at":"now","started_at":"then","stale":false,"recent":[{"text":"开始处理","at":"now"}]}]}"#
        let snapshot = try JSONDecoder().decode(TaskDashboardSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.tasks[0].displayTitle, "未命名任务 · t")
        XCTAssertEqual(snapshot.tasks[0].recent.count, 1)
        XCTAssertNotEqual(TaskTime.label(snapshot.updatedAt), "时间未知")
        XCTAssertEqual(TaskTime.label("invalid"), "时间未知")
        XCTAssertNotNil(ApprovalClient.endpoint(base: "https://example.com", path: "/tasks"))
        XCTAssertNil(ApprovalClient.endpoint(base: "https://example.com", path: "/tasks/other"))
    }
    func testProjectGroupsKeepDistinctIDsAndFilterActivity() {
        var a = task("a", "running"); a.projectID = "one"
        var b = task("b", "untracked"); b.projectID = "two"
        var c = task("c", "needs_approval"); c.projectID = "one"
        let snapshot = TaskDashboardSnapshot(updatedAt: "now", tasks: [a, b, c])
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false).map(\.id), ["one", "two"])
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false)[0].tasks.map(\.id), ["a", "c"])
        XCTAssertEqual(snapshot.projectGroups(activeOnly: true).map(\.id), ["one"])
        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertEqual(snapshot.attentionCount, 1)
        XCTAssertEqual(b.statusLabel, "尚未监测")
    }
    func testDesktopNamesAndProjectIDDecodeAlongsideLegacyPayloads() throws {
        let json = #"{"updated_at":"now","tasks":[{"id":"abcdef123","title":"侧栏任务标题","project":"项目","project_id":"project-1","status":"untracked","phase":"尚未采集到任务活动","updated_at":"","started_at":"","stale":false,"recent":[]}]}"#
        let snapshot = try JSONDecoder().decode(TaskDashboardSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.tasks[0].displayTitle, "侧栏任务标题")
        XCTAssertEqual(snapshot.tasks[0].projectID, "project-1")
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false)[0].name, "项目")
        XCTAssertTrue(snapshot.projectGroups(activeOnly: true).isEmpty)
        XCTAssertEqual(task("abcdef", "finished").groupingID, "legacy:Project")
    }
    func testDesktopProjectOrderIncludesEmptyProjectsAndSurvivesActivityFilter() {
        var a = task("a", "running"); a.projectID = "one"
        var b = task("b", "running"); b.projectID = "two"
        var snapshot = TaskDashboardSnapshot(updatedAt: "now", tasks: [a, b])
        snapshot.projects = [DashboardProject(id: "two", name: "Second"),
                             DashboardProject(id: "empty", name: "Empty"),
                             DashboardProject(id: "one", name: "First")]
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false).map(\.id), ["two", "empty", "one"])
        XCTAssertTrue(snapshot.projectGroups(activeOnly: false)[1].tasks.isEmpty)
        XCTAssertEqual(snapshot.projectGroups(activeOnly: true).map(\.id), ["two", "one"])
        snapshot.projects?.reverse()
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false).map(\.id), ["one", "empty", "two"])
    }
    func testProjectManifestDecodesAndUnknownGroupsRemainVisible() throws {
        let json = #"{"updated_at":"now","projects":[{"id":"empty","name":"Empty"}],"tasks":[]}"#
        var snapshot = try JSONDecoder().decode(TaskDashboardSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false).map(\.id), ["empty"])
        snapshot = TaskDashboardSnapshot(updatedAt: "now", tasks: [task("free", "finished")], projects: snapshot.projects)
        XCTAssertEqual(snapshot.projectGroups(activeOnly: false).map(\.id), ["empty", "legacy:Project"])
    }
    private func task(_ id: String, _ status: String, stale: Bool = false) -> DashboardTask {
        DashboardTask(id: id, project: "Project", title: nil, status: status, phase: "phase", updatedAt: "now", startedAt: "then", stale: stale, recent: [])
    }
}
