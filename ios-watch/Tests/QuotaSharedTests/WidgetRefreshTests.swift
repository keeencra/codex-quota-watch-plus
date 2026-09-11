import XCTest
@testable import QuotaShared

final class WidgetRefreshTests: XCTestCase {
    func testNetworkRefreshReplacesPhoneCache() async {
        let suite = "test.widget." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedUsageStore(defaults: defaults)
        var old = WatchSnapshot.placeholder
        old.updatedAt = "2026-09-11T08:00:00Z"
        old.codex.remainingPercent = 23
        store.save(old)
        var live = old
        live.updatedAt = "2026-09-11T09:00:00Z"
        live.codex.remainingPercent = 13
        let result = await WidgetSnapshotFetcher.refresh(store: store) { live }
        XCTAssertFalse(result.failed)
        XCTAssertEqual(result.snapshot?.codex.remainingPercent, 13)
        XCTAssertEqual(store.loadOptional()?.codex.remainingPercent, 13)
        XCTAssertEqual(store.loadOptional()?.updatedAt, live.updatedAt)
    }

    func testOfflineRefreshPreservesValueAndOriginalTimestamp() async {
        let suite = "test.widget." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedUsageStore(defaults: defaults)
        var cached = WatchSnapshot.placeholder
        cached.updatedAt = "2026-09-11T08:00:00Z"
        cached.codex.remainingPercent = 23
        store.save(cached)
        let result = await WidgetSnapshotFetcher.refresh(store: store) {
            throw UsageClientError.network("offline", code: -1009)
        }
        XCTAssertTrue(result.failed)
        XCTAssertEqual(result.snapshot?.codex.remainingPercent, 23)
        XCTAssertEqual(result.snapshot?.updatedAt, cached.updatedAt)
        XCTAssertEqual(store.loadOptional()?.updatedAt, cached.updatedAt)
    }

    func testUnpairedWidgetDoesNotInventSnapshot() async {
        let suite = "test.widget." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedUsageStore(defaults: defaults)
        let result = await WidgetSnapshotFetcher.refresh(store: store) {
            throw UsageClientError.emptyToken
        }
        XCTAssertTrue(result.failed)
        XCTAssertNil(result.snapshot)
        XCTAssertNil(store.loadOptional())
    }
}
