import XCTest
@testable import QuotaShared

final class RemoteEndpointTests: XCTestCase {
    func testMigrationUpdatesKnownEndpointOnceAndPreservesToken() {
        let suite = "test.remote." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("http://198.51.100.10:8787/", forKey: "url")
        defaults.set("secret", forKey: "token")
        let destination = "https://quota.example.com"
        RemoteEndpointMigration.apply(defaults: defaults, key: "url", destination: destination, previousURLs: ["http://198.51.100.10:8787"])
        XCTAssertEqual(defaults.string(forKey: "url"), destination)
        XCTAssertEqual(defaults.string(forKey: "token"), "secret")
        defaults.set("http://198.51.100.10:8787", forKey: "url")
        RemoteEndpointMigration.apply(defaults: defaults, key: "url", destination: destination, previousURLs: ["http://198.51.100.10:8787"])
        XCTAssertEqual(defaults.string(forKey: "url"), "http://198.51.100.10:8787")
    }

    func testMigrationPreservesCustomEndpointAndRejectsInvalidDestination() {
        let suite = "test.remote." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://my.example.com", forKey: "url")
        RemoteEndpointMigration.apply(defaults: defaults, key: "url", destination: "https://quota.example.com", previousURLs: [])
        XCTAssertEqual(defaults.string(forKey: "url"), "https://my.example.com")
        for destination in ["http://quota.example.com", "https://user:pass@quota.example.com"] {
            RemoteEndpointMigration.apply(defaults: defaults, key: "new", destination: destination, previousURLs: [])
            XCTAssertNil(defaults.string(forKey: "new"))
        }
        RemoteEndpointMigration.apply(defaults: defaults, key: "new", destination: "https://quota.example.com", previousURLs: [])
        XCTAssertEqual(defaults.string(forKey: "new"), "https://quota.example.com")
    }
}
