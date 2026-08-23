import Foundation
import CryptoKit

/// Credentials CalmMeter minted itself via the OAuth flow (as opposed to
/// `ClaudeCredentials` read from Claude Code's keychain item). Holds the refresh
/// token, so CalmMeter can keep itself signed in without Claude Code.
public struct OAuthCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let accountEmail: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, accountEmail: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountEmail = accountEmail
    }
}

public enum OAuthError: Error, Equatable {
    /// The pasted string is not in the expected `CODE#STATE` shape.
    case malformedCode
    /// The pasted state does not match the one this sign-in attempt sent out.
    case stateMismatch
    /// The token endpoint rejected the grant (HTTP 400/401) — the code or
    /// refresh token is expired, revoked, or already used.
    case invalidGrant
    case http(Int)
    case offline
    case decoding(String)
}

/// The OAuth flow Claude Code itself uses, reused by CalmMeter so users without
/// Claude Code can sign in directly.
///
/// AIDEV-NOTE: clientID is Claude Code's own public OAuth client id (ADR-0001).
/// Unofficial API surface — Anthropic may rotate or block it. Don't invent a new
/// one; there is no public client registration for this flow.
public enum ClaudeOAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    public static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scope = "user:inference user:profile user:sessions:claude_code user:mcp_servers"

    public static func authorizeURL(challenge: String, state: String) -> URL {
        var comps = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return comps.url!
    }

    /// Parses the `CODE#STATE` string the callback page tells the user to copy.
    /// Splits on the FIRST `#` — the state itself may contain `#`.
    public static func parsePastedCode(_ raw: String) throws -> (code: String, state: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.firstIndex(of: "#") else { throw OAuthError.malformedCode }
        let code = String(trimmed[..<hash])
        let state = String(trimmed[trimmed.index(after: hash)...])
        guard !code.isEmpty, !state.isEmpty else { throw OAuthError.malformedCode }
        return (code, state)
    }

    public static func exchangeRequestBody(code: String, verifier: String, state: String) -> Data {
        formEncode([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", verifier),
            ("state", state),
        ])
    }

    public static func refreshRequestBody(refreshToken: String) -> Data {
        formEncode([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
        ])
    }

    static func formEncode(_ pairs: [(String, String)]) -> Data {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        let encoded = pairs.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
            return "\(k)=\(v)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    private struct TokenResponse: Decodable {
        struct Account: Decodable {
            let email_address: String?
        }
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let account: Account?
    }

    /// Decodes a token-endpoint response (exchange or refresh). A refresh
    /// response may omit `refresh_token` (RFC 6749 §6) — pass the current one so
    /// it carries forward; with neither present the credentials are unusable.
    public static func decodeTokenResponse(
        _ data: Data,
        now: Date = Date(),
        currentRefreshToken: String? = nil
    ) throws -> OAuthCredentials {
        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw OAuthError.decoding(String(describing: error))
        }
        guard let refreshToken = response.refresh_token ?? currentRefreshToken else {
            throw OAuthError.decoding("response has no refresh_token and none carried over")
        }
        return OAuthCredentials(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(response.expires_in),
            accountEmail: response.account?.email_address
        )
    }
}

/// One sign-in attempt's PKCE material (RFC 7636) plus the CSRF `state`.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init() {
        verifier = Self.randomBase64URL(byteCount: 32)
        challenge = Self.challenge(for: verifier)
        state = Self.randomBase64URL(byteCount: 32)
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        // SystemRandomNumberGenerator is cryptographically secure on Apple
        // platforms and, unlike SecRandomCopyBytes, has no failure path.
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
