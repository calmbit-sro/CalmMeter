import Foundation

public enum UsageClientError: Error, LocalizedError, Equatable {
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case http(Int)
    case offline
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized (token rejected)."
        case .rateLimited: return "Rate limited (HTTP 429)."
        case .http(let code): return "Server error (HTTP \(code))."
        case .offline: return "Offline / network error."
        case .decoding(let detail): return "Unexpected response: \(detail)"
        }
    }

    /// Suggested seconds to wait before retrying, when the server told us.
    public var retryAfter: Int? {
        if case .rateLimited(let seconds) = self { return seconds }
        return nil
    }
}

/// Talks to `GET https://api.anthropic.com/api/oauth/usage` using the OAuth
/// bearer token, exactly like Claude Code's `/usage`.
public struct UsageClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    private let provider: CredentialProviding

    public init(
        session: URLSession = .shared,
        provider: CredentialProviding = CachedCredentialProvider()
    ) {
        self.session = session
        self.provider = provider
    }

    /// Convenience for tests: build a client from a plain closure token source.
    public init(session: URLSession = .shared,
                credentialsProvider: @escaping () throws -> ClaudeCredentials) {
        self.session = session
        self.provider = AnyCredentialProvider { _ in try credentialsProvider() }
    }

    public func fetch() async throws -> Usage {
        // Use the cached token; if it's been rejected, re-read Claude Code's
        // keychain item once (this is the only path that may prompt) and retry.
        do {
            return try await attempt(forceRefresh: false)
        } catch UsageClientError.unauthorized {
            return try await attempt(forceRefresh: true)
        }
    }

    private func attempt(forceRefresh: Bool) async throws -> Usage {
        let creds = try provider.credentials(forceRefresh: forceRefresh)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageClientError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.decoding("no HTTP response")
        }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw UsageClientError.unauthorized
        case 429: throw UsageClientError.rateLimited(retryAfter: Self.retryAfterSeconds(http))
        default: throw UsageClientError.http(http.statusCode)
        }

        return try Self.decode(data)
    }

    /// Parses a `Retry-After` header (seconds form) if present.
    static func retryAfterSeconds(_ http: HTTPURLResponse) -> Int? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    /// Decoding split out for unit testing against fixtures.
    public static func decode(_ data: Data) throws -> Usage {
        do {
            return try JSONDecoder().decode(Usage.self, from: data)
        } catch {
            throw UsageClientError.decoding(String(describing: error))
        }
    }
}
