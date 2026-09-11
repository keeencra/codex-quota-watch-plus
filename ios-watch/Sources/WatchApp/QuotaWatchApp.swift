import SwiftUI

@main
struct QuotaWatchApp: App {
    init() {
        RemoteEndpointMigration.applyBundled(key: AppConstants.directMacURLKey)
    }
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
