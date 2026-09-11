import Foundation

public final class UsageClient {
    public static let watchRequestTimeoutSeconds: TimeInterval = 20

    public init() {}

    public func configureBark(macAgentBaseURL: String, token: String, address: String) async throws {
        guard var components = URLComponents(string: macAgentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil else {
            throw UsageClientError.invalidURL
        }
        guard !token.isEmpty else { throw UsageClientError.emptyToken }
        components.path = "/notifications/bark"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw UsageClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(token, forHTTPHeaderField: "x-watch-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["address": address])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UsageClientError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    public static func watchURL(macAgentBaseURL: String, forceRefresh: Bool = true) -> URL? {
        var base = macAgentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + "/watch") else { return nil }
        if forceRefresh {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "force", value: "1")]
        }
        return components.url
    }

    public func fetchCompact(
        macAgentBaseURL: String,
        token: String?,
        timeoutSeconds: TimeInterval = watchRequestTimeoutSeconds,
        forceRefresh: Bool = true
    ) async throws -> WatchSnapshot {
        guard let url = Self.watchURL(macAgentBaseURL: macAgentBaseURL, forceRefresh: forceRefresh) else {
            throw UsageClientError.invalidURL
        }
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageClientError.emptyToken
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        request.setValue(token, forHTTPHeaderField: "x-watch-token")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw UsageClientError.network(error.localizedDescription, code: error.errorCode)
        } catch {
            throw UsageClientError.network(error.localizedDescription, code: nil)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UsageClientError.badResponse(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(WatchSnapshot.self, from: data)
        } catch {
            throw UsageClientError.invalidPayload(error.localizedDescription)
        }
    }
}

/// Fetches independently of the iPhone foreground lifecycle, preserving the last
/// successful snapshot (and its timestamp) when the network is unavailable.
public enum WidgetSnapshotFetcher {
    public struct Result {
        public let snapshot: WatchSnapshot?
        public let failed: Bool
    }

    public static func refresh(
        store: SharedUsageStore = .shared,
        fetch: () async throws -> WatchSnapshot
    ) async -> Result {
        do {
            let snapshot = try await fetch()
            store.save(snapshot)
            return Result(snapshot: snapshot, failed: false)
        } catch {
            return Result(snapshot: store.loadOptional(), failed: true)
        }
    }
}

private final class ApprovalNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ApprovalClient {
    public static func endpoint(base: String, path: String) -> URL? {
        guard var parts = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              (path.hasPrefix("/approvals") || path == "/tasks") else { return nil }
        parts.path = path
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    private static func send(base: String, token: String, path: String, body: [String: String]? = nil) async throws -> Data {
        guard let url = endpoint(base: base, path: path) else { throw UsageClientError.invalidURL }
        guard !token.isEmpty else { throw UsageClientError.emptyToken }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(token, forHTTPHeaderField: "x-watch-token")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let session = URLSession(configuration: .ephemeral, delegate: ApprovalNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UsageClientError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    public static func list(base: String, token: String) async throws -> RemoteApprovalList {
        try JSONDecoder().decode(RemoteApprovalList.self, from: await send(base: base, token: token, path: "/approvals"))
    }
    public static func tasks(base: String, token: String) async throws -> TaskDashboardSnapshot {
        try JSONDecoder().decode(TaskDashboardSnapshot.self, from: await send(base: base, token: token, path: "/tasks"))
    }
    public static func status(base: String, token: String, id: String) async throws -> RemoteApproval {
        guard id.range(of: "^[A-Za-z0-9_-]{32}$", options: .regularExpression) != nil else { throw UsageClientError.invalidURL }
        return try JSONDecoder().decode(RemoteApproval.self, from: await send(base: base, token: token, path: "/approvals/" + id))
    }
    public static func decide(base: String, token: String, request: RemoteApproval, allow: Bool) async throws {
        guard request.canDecide(), request.id.range(of: "^[A-Za-z0-9_-]{32}$", options: .regularExpression) != nil else { throw UsageClientError.badResponse(409) }
        _ = try await send(base: base, token: token, path: "/approvals/" + request.id + "/decision", body: [
            "nonce": request.nonce, "fingerprint": request.fingerprint, "decision": allow ? "allow" : "deny"
        ])
    }
}

#if canImport(SwiftUI)
import SwiftUI

public struct ApprovalInboxView: View {
    let base: String
    let token: String
    @State private var requests: [RemoteApproval] = []
    @State private var message = "正在连接 Mac…"
    @State private var loading = false

    public init(base: String, token: String) { self.base = base; self.token = token }

    public var body: some View {
        List {
            Section {
                Label("逐项确认", systemImage: "checkmark.shield")
                    .font(.headline).foregroundStyle(.orange)
                Text("只批准你正在查看的这一次操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if requests.isEmpty {
                Text(message).font(.callout)
            }
            ForEach(requests) { request in
                NavigationLink {
                    ApprovalDetailView(base: base, token: token, initial: request)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(request.project).font(.headline)
                        Label(request.tool, systemImage: "hand.raised.fill")
                            .font(.caption).foregroundStyle(.orange)
                        Text("查看操作详情").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Button("刷新") { Task { await refresh() } }.disabled(loading)
            Text("Bark 提醒后，请打开本页。未出现在这里的授权或提问，请在 Mac 处理。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("待审批")
        .task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            }
        }
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await ApprovalClient.list(base: base, token: token)
            requests = result.requests
            message = result.enabled ? "当前没有待审批操作" : "Mac 尚未启用远程审批"
        } catch {
            requests = []
            message = "连接失败，请检查网络后刷新。"
        }
    }
}

private struct ApprovalDetailView: View {
    let base: String
    let token: String
    let initial: RemoteApproval
    @State private var current: RemoteApproval?
    @State private var busy = false
    @State private var confirmation = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(initial.project).font(.headline)
                Label(initial.tool, systemImage: "terminal").font(.subheadline)
                Text("操作详情").font(.caption).foregroundStyle(.secondary)
                Text(initial.details).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let current {
                    Text(current.statusLabel).font(.footnote).foregroundStyle(.orange)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if current.canDecide(at: context.date) {
                            Text("剩余 \(max(0, Int(current.expires - context.date.timeIntervalSince1970))) 秒")
                                .font(.caption).monospacedDigit()
                            Button("批准本次") { confirmation = true }
                                .buttonStyle(.borderedProminent).tint(.green).disabled(busy)
                            Button("拒绝本次", role: .destructive) { Task { await decide(false) } }
                                .buttonStyle(.bordered).disabled(busy)
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Button("核对最新状态") { Task { await refresh() } }.disabled(busy)
                Text("决定交回 Codex 后，仍由 Codex 检查其他规则并执行。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("确认操作")
        .confirmationDialog("允许上方完整操作执行一次？", isPresented: $confirmation, titleVisibility: .visible) {
            Button("确认批准本次") { Task { await decide(true) } }
            Button("取消", role: .cancel) {}
        }
        .task { await refresh() }
    }

    @MainActor private func refresh() async {
        do {
            let result = try await ApprovalClient.status(base: base, token: token, id: initial.id)
            guard result.fingerprint == initial.fingerprint else { current = nil; message = "请求已变化，请返回列表重新查看。"; return }
            current = result
        } catch { current = nil; message = "无法核对请求，请连接后重试。" }
    }

    @MainActor private func decide(_ allow: Bool) async {
        guard !busy, let request = current, request.canDecide() else { return }
        busy = true
        defer { busy = false }
        do {
            try await ApprovalClient.decide(base: base, token: token, request: request, allow: allow)
            current = nil
            message = "决定已提交，正在核对 Mac 回执…"
            for _ in 0..<8 {
                let result = try await ApprovalClient.status(base: base, token: token, id: request.id)
                current = result
                if result.status != "submitted" { message = nil; return }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            message = "尚未确认 Mac 已接收，请核对最新状态。"
        } catch {
            current = nil
            message = "尚不能确认结果，请核对最新状态；不会自动重发批准。"
        }
    }
}
#endif
