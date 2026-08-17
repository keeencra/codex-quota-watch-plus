import BackgroundTasks
import SwiftUI
import WidgetKit

@main
struct QuotaPhoneApp: App {
    init() {
        _ = PhoneConnectivity.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .backgroundTask(.appRefresh(AppConstants.backgroundRefreshTaskID)) {
            await BackgroundRefreshService.runScheduledRefresh()
        }
    }
}

enum BackgroundRefreshResult {
    case success(WatchSnapshot)
    case failure(String)
}

enum BackgroundRefreshService {
    private static let refreshInterval: TimeInterval = 15 * 60

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    private static var storedMacURL: String {
        defaults.string(forKey: AppConstants.macURLKey) ?? "http://127.0.0.1:8787"
    }

    private static var storedToken: String {
        WatchTokenStore.migrateLegacyTokenIfNeeded(defaults: defaults)
    }

    static func scheduleIfEnabled() {
        let enabled = defaults.object(forKey: AppConstants.autoRefreshKey) as? Bool ?? true
        guard enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConstants.backgroundRefreshTaskID)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConstants.backgroundRefreshTaskID)
    }

    static func fetchAndSync(macURL: String, token: String) async throws -> WatchSnapshot {
        let result = try await UsageClient().fetchCompact(macAgentBaseURL: macURL, token: token)
        await MainActor.run {
            SharedUsageStore.shared.save(result)
            WidgetCenter.shared.reloadAllTimelines()
            PhoneConnectivity.shared.send(snapshot: result, macURL: macURL, token: token)
        }
        return result
    }

    static func runWatchRequestedRefresh() async -> BackgroundRefreshResult {
        scheduleIfEnabled()
        do {
            let snapshot = try await fetchAndSync(macURL: storedMacURL, token: storedToken)
            return .success(snapshot)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func runScheduledRefresh() async {
        scheduleIfEnabled()
        _ = try? await fetchAndSync(macURL: storedMacURL, token: storedToken)
    }
}
