import Foundation
import WatchConnectivity
import WidgetKit

final class WatchConnectivityReceiver: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityReceiver()

    @Published var snapshot: WatchSnapshot = SharedUsageStore.shared.load()
    @Published var refreshRoute: WatchRefreshRoute = .cached
    private var pendingRefreshRequest = false
    private var directRefreshTask: Task<Void, Never>?
    private var lastPhoneRelayRequestAt: Date?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func requestRefresh() {
        reloadCachedSnapshot()
        let now = Date()
        if WatchRefreshPolicy.requestsPhoneRelayOnOpen,
           WatchRefreshPolicy.shouldRequestPhoneRelay(lastRequestAt: lastPhoneRelayRequestAt, now: now) {
            lastPhoneRelayRequestAt = now
            requestRefreshFromPhone()
        }
        guard directRefreshTask == nil else { return }
        refreshRoute = .directRefreshing
        directRefreshTask = Task { [weak self] in
            guard let self else { return }
            let didRefresh = await self.refreshDirectlyFromMac()
            await MainActor.run {
                self.directRefreshTask = nil
                if !didRefresh {
                    // The first relay request can race with WatchConnectivity
                    // activation. Re-send after a failed direct fetch; the
                    // debounce prevents a tight request loop.
                    self.requestRefreshFromPhone()
                }
            }
        }
    }

    func reloadCachedSnapshot() {
        snapshot = SharedUsageStore.shared.load()
    }

    private func refreshDirectlyFromMac() async -> Bool {
        guard let config = WatchAgentConfigStore().load() else {
            await MainActor.run {
                self.refreshRoute = .noConfig
            }
            return false
        }

        do {
            let updatedSnapshot = try await UsageClient().fetchCompact(
                macAgentBaseURL: config.macURL,
                token: config.token,
                timeoutSeconds: WatchRefreshPolicy.directRefreshTimeoutSeconds
            )
            await MainActor.run {
                self.adopt(updatedSnapshot, route: .directOK)
            }
            return true
        } catch {
            await MainActor.run {
                self.refreshRoute = .directFailed(WatchRefreshErrorText.directFailureDetail(error))
            }
            return false
        }
    }

    private func requestRefreshFromPhone() {
        guard WCSession.isSupported() else { return }
        let payload = RefreshRequestPayload.make(reason: "watch-opened")
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingRefreshRequest = true
            return
        }
        pendingRefreshRequest = false
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func apply(_ applicationContext: [String: Any]) {
        if let config = WatchAgentConfig.make(from: applicationContext) {
            WatchAgentConfigStore().save(config)
        }

        let decodedSnapshot: WatchSnapshot?
        if let json = applicationContext[AppConstants.snapshotKey] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            decodedSnapshot = decoded
        } else {
            decodedSnapshot = nil
        }

        guard decodedSnapshot != nil else { return }

        DispatchQueue.main.async {
            if let decodedSnapshot {
                self.adopt(decodedSnapshot, route: .iPhone)
            }
        }
    }

    private func adopt(_ incoming: WatchSnapshot, route: WatchRefreshRoute) {
        guard WatchSnapshotFreshness.incoming(incoming, isAtLeastAsNewAs: snapshot) else {
            return
        }
        let changed = incoming != snapshot
        snapshot = incoming
        SharedUsageStore.shared.save(incoming)
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: "QuotaWatchComplication")
        }
        refreshRoute = route
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        apply(session.receivedApplicationContext)
        DispatchQueue.main.async {
            if self.pendingRefreshRequest {
                self.requestRefresh()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        apply(message)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        requestRefreshFromPhone()
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
