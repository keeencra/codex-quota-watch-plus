import Foundation
import WatchConnectivity

final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()
    static let refreshRequestNotification = Notification.Name("PhoneConnectivityRefreshRequest")
    private var watchRefreshTask: Task<Void, Never>?

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
                return "not paired"
            }
            if !session.isWatchAppInstalled {
                return "app not installed"
            }
            return session.isReachable ? "reachable" : "installed"
        @unknown default:
            return "unknown"
        }
    }

    func send(snapshot: WatchSnapshot, macURL: String, token: String) {
        guard WCSession.isSupported() else { return }
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }

        let context = context(snapshotJSON: json, macURL: macURL, token: token)
        try? WCSession.default.updateApplicationContext(context)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(context, replyHandler: nil, errorHandler: nil)
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

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
