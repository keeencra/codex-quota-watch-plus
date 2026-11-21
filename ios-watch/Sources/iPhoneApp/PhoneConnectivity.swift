import Foundation
import WatchConnectivity

final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()
    static let refreshRequestNotification = Notification.Name("PhoneConnectivityRefreshRequest")
    private var watchRefreshTask: Task<Void, Never>?
    private(set) var lastDeliveryError: String?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var diagnosticsStatus: String {
        guard WCSession.isSupported() else { return "unsupported" }
        let session = WCSession.default
        switch session.activationState {
        case .notActivated:
            return "not activated"
        case .inactive:
            return "inactive"
        case .activated:
            if !session.isPaired {
                return "未配对（可选，不影响手机使用）"
            }
            if !session.isWatchAppInstalled {
                return "手表已配对，安装状态待刷新"
            }
            return session.isReachable ? "reachable" : "installed"
        @unknown default:
            return "unknown"
        }
    }

    func send(snapshot: WatchSnapshot, macURL: String, token: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }

        let context = context(snapshotJSON: json, macURL: macURL, token: token)
        deliver(context, through: session)
    }

    /// Replays the newest local snapshot when WatchConnectivity finishes
    /// activation. `isWatchAppInstalled` can remain stale after a reinstall,
    /// so it must not gate delivery.
    func resendLatestSnapshot() {
        guard let snapshot = SharedUsageStore.shared.loadOptional() else { return }
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let macURL = defaults.string(forKey: AppConstants.macURLKey) ?? "http://127.0.0.1:8787"
        let token = WatchTokenStore.migrateLegacyTokenIfNeeded(defaults: defaults)
        send(snapshot: snapshot, macURL: macURL, token: token)
    }

    private func deliver(_ context: [String: Any], through session: WCSession) {
        do {
            try session.updateApplicationContext(context)
            lastDeliveryError = nil
        } catch {
            lastDeliveryError = error.localizedDescription
            // transferUserInfo is queued by the system and survives a temporary
            // watch disconnect or a delayed app activation.
            session.transferUserInfo(context)
        }
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { [weak self] error in
                self?.lastDeliveryError = error.localizedDescription
            }
        }
    }

    private func context(snapshotJSON: String?, macURL: String, token: String) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let snapshotJSON {
            payload[AppConstants.snapshotKey] = snapshotJSON
        }
        if let config = WatchAgentConfig.make(macURL: macURL, token: token) {
            payload.merge(config.payload) { _, new in new }
        }
        return payload
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, error == nil else { return }
        resendLatestSnapshot()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        resendLatestSnapshot()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        resendLatestSnapshot()
    }

    private func handleRefreshRequest(_ payload: [String: Any]) {
        guard RefreshRequestPayload.isRefreshRequest(payload) else { return }
        DispatchQueue.main.async {
            self.startWatchRequestedRefresh()
        }
    }

    @MainActor
    private func startWatchRequestedRefresh() {
        guard watchRefreshTask == nil else { return }
        watchRefreshTask = Task {
            let result = await BackgroundRefreshService.runWatchRequestedRefresh()
            await MainActor.run {
                self.watchRefreshTask = nil
                NotificationCenter.default.post(name: Self.refreshRequestNotification, object: result)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleRefreshRequest(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        handleRefreshRequest(userInfo)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
