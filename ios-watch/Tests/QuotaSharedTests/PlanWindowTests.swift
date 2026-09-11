import XCTest
@testable import QuotaShared

final class PlanWindowTests: XCTestCase {
    func testProWeeklyQuotaDoesNotCreateFiveHourWindow() throws {
        var usage = ProviderUsage.placeholder(status: "ok")
        usage.planType = "prolite"
        usage.buckets = [
            QuotaBucket(id: "codex_bengalfox:primary", label: "Special 5h", remainingPercent: 100, usedPercent: 0, resetIn: "1h", window: "5h", status: "ok"),
            QuotaBucket(id: "codex:primary", label: "Codex 7d", remainingPercent: 34, usedPercent: 66, resetIn: "6d", window: "7d", status: "ok")
        ]
        let decoded = try JSONDecoder().decode(ProviderUsage.self, from: JSONEncoder().encode(usage))
        XCTAssertEqual(decoded.planType, "prolite")
        XCTAssertEqual(decoded.planLabel, "Pro")
        let selection = WatchDisplayData.codexWindows(from: decoded.buckets)
        XCTAssertNil(selection.fiveHour)
        XCTAssertEqual(selection.windows.map(\.window), ["7d"])
        let summary = WidgetQuotaSummary(snapshot: WatchSnapshot(updatedAt: "2026-09-11T08:00:00Z", codex: decoded))
        XCTAssertEqual(summary.planLabel, "Pro")
        XCTAssertNil(summary.fiveHour)
        XCTAssertEqual(summary.windows.count, 1)
        XCTAssertEqual(summary.windows.first?.title, "7 天")
        XCTAssertEqual(summary.windows.first?.percentLabel, "34%")
    }

    func testPlanLabelsAndMissingMetadata() {
        var usage = ProviderUsage.placeholder(status: "ok")
        for (raw, label) in [("plus", "Plus"), ("pro", "Pro"), ("prolite", "Pro"), ("future", "套餐未知")] {
            usage.planType = raw
            XCTAssertEqual(usage.planLabel, label)
        }
        usage.planType = nil
        XCTAssertEqual(usage.planLabel, "套餐未知")
    }

    func testPlusAndProUseActualWindowsRatherThanPlanAssumptions() {
        for plan in ["plus", "pro"] {
            var usage = ProviderUsage.placeholder(status: "ok")
            usage.planType = plan
            usage.buckets = [
                QuotaBucket(id: "codex:primary", label: nil, remainingPercent: 80, usedPercent: 20, resetIn: "1h", window: "5h", status: "ok"),
                QuotaBucket(id: "codex:secondary", label: nil, remainingPercent: 30, usedPercent: 70, resetIn: "6d", window: "7d", status: "ok")
            ]
            XCTAssertEqual(WatchDisplayData.codexWindows(from: usage.buckets).windows.map(\.window), ["5h", "7d"])
        }
        let unknown = QuotaBucket(id: "codex:primary", label: nil, remainingPercent: 80, usedPercent: nil, resetIn: nil, window: "1d", status: "ok")
        let selection = WatchDisplayData.codexWindows(from: [unknown])
        XCTAssertNil(selection.fiveHour)
        XCTAssertEqual(selection.windows.map(\.window), ["1d"])
    }

    func testMissingWindowDataDoesNotBorrowWeeklyPercentage() {
        var usage = ProviderUsage.placeholder(status: "ok")
        usage.remainingPercent = 34
        let bucket = QuotaBucket(id: "codex:primary", label: nil, remainingPercent: nil, usedPercent: nil, resetIn: nil, window: "5h", status: "partial")
        XCTAssertNil(QuotaDisplayText.remainingPercent(bucket: bucket, fallback: usage))
    }
}
