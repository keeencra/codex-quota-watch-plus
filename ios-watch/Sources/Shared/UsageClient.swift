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
