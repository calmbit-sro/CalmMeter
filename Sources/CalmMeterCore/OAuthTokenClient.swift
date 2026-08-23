import Foundation

/// Talks to the OAuth token endpoint: authorization-code exchange (sign-in) and
/// refresh-token grant. All request/response shaping lives in `ClaudeOAuth`
/// statics; this only does the HTTP round-trip and status mapping.
public struct OAuthTokenClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func exchange(code: String, verifier: String, state: String) async throws -> OAuthCredentials {
        try await post(
            body: ClaudeOAuth.exchangeRequestBody(code: code, verifier: verifier, state: state),
            currentRefreshToken: nil
        )
    }

    public func refresh(refreshToken: String) async throws -> OAuthCredentials {
        try await post(
            body: ClaudeOAuth.refreshRequestBody(refreshToken: refreshToken),
            currentRefreshToken: refreshToken
        )
    }

    private func post(body: Data, currentRefreshToken: String?) async throws -> OAuthCredentials {
        var request = URLRequest(url: ClaudeOAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OAuthError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.decoding("no HTTP response")
        }
        switch http.statusCode {
        case 200: break
        case 400, 401: throw OAuthError.invalidGrant
        default: throw OAuthError.http(http.statusCode)
        }

        let creds = try ClaudeOAuth.decodeTokenResponse(data, currentRefreshToken: currentRefreshToken)
        #if DEBUG
        // Shrink token lifetime for fast live refresh testing (dev builds only).
        if let raw = ProcessInfo.processInfo.environment["CALMMETER_TEST_EXPIRES_IN"],
           let seconds = TimeInterval(raw) {
            return OAuthCredentials(
                accessToken: creds.accessToken,
                refreshToken: creds.refreshToken,
                expiresAt: Date().addingTimeInterval(seconds),
                accountEmail: creds.accountEmail
            )
        }
        #endif
        return creds
    }
}
