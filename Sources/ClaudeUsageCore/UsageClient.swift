import Foundation

public enum UsageClientError: Error, LocalizedError, Equatable {
    case unauthorized
    case http(Int)
    case offline
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Přihlášení vypršelo — spusť `claude` a přihlaš se znovu."
        case .http(let code):
            return "Server vrátil chybu (HTTP \(code))."
        case .offline:
            return "Bez připojení."
        case .decoding(let detail):
            return "Nečekaná odpověď serveru: \(detail)"
        }
    }
}

/// Talks to `GET https://api.anthropic.com/api/oauth/usage` using the OAuth
/// bearer token, exactly like Claude Code's `/usage`.
public struct UsageClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    private let credentialsProvider: () throws -> ClaudeCredentials

    public init(
        session: URLSession = .shared,
        credentialsProvider: @escaping () throws -> ClaudeCredentials = Keychain.readCredentials
    ) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    public func fetch() async throws -> Usage {
        let creds = try credentialsProvider()

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
        default: throw UsageClientError.http(http.statusCode)
        }

        return try Self.decode(data)
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
