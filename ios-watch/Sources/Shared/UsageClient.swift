import Foundation

public final class UsageClient {
    public static let watchRequestTimeoutSeconds: TimeInterval = 20

    public init() {}

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
