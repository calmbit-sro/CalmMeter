import XCTest
@testable import CalmMeterCore

/// Pure OAuth building blocks: PKCE generation, authorize-URL construction,
/// pasted-code parsing, request bodies and token-response decoding. No network.
final class OAuthTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    /// Decodes an `application/x-www-form-urlencoded` body back into a dictionary.
    private func formFields(_ body: Data) throws -> [String: String] {
        let string = try XCTUnwrap(String(data: body, encoding: .utf8))
        var fields = [String: String]()
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = try XCTUnwrap(String(parts[0]).removingPercentEncoding)
            let value = try XCTUnwrap(String(parts.count > 1 ? parts[1] : "").removingPercentEncoding)
            fields[key] = value
        }
        return fields
    }

    // MARK: PKCE

    func testVerifierIs43CharBase64URL() {
        let pkce = PKCE()
        XCTAssertEqual(pkce.verifier.count, 43, "32 random bytes → 43 base64url chars")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains),
                      "verifier must use only unreserved base64url characters")
    }

    func testChallengeMatchesRFC7636Vector() {
        // RFC 7636 Appendix B reference vector.
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testEachPKCEIsUnique() {
        let a = PKCE()
        let b = PKCE()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.state, b.state)
        XCTAssertNotEqual(a.verifier, a.state, "state must not reuse the verifier's bytes")
    }

    // MARK: Authorize URL

    func testAuthorizeURLContainsExactParams() throws {
        let url = ClaudeOAuth.authorizeURL(challenge: "CHAL", state: "STATE")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.scheme, "https")
        XCTAssertEqual(comps.host, "claude.ai")
        XCTAssertEqual(comps.path, "/oauth/authorize")

        var params = [String: String]()
        for item in comps.queryItems ?? [] { params[item.name] = item.value }
        XCTAssertEqual(params["code"], "true")
        XCTAssertEqual(params["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["redirect_uri"], "https://platform.claude.com/oauth/code/callback")
        XCTAssertEqual(params["scope"], "user:inference user:profile user:sessions:claude_code user:mcp_servers")
        XCTAssertEqual(params["code_challenge"], "CHAL")
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertEqual(params["state"], "STATE")
        XCTAssertEqual(params.count, 8)
    }

    // MARK: Pasted-code parsing

    func testParsePastedCodeSplitsOnFirstHash() throws {
        let parsed = try ClaudeOAuth.parsePastedCode("abc123#state456#tail")
        XCTAssertEqual(parsed.code, "abc123")
        XCTAssertEqual(parsed.state, "state456#tail")
    }

    func testParsePastedCodeTrimsWhitespace() throws {
        let parsed = try ClaudeOAuth.parsePastedCode("  abc#def\n")
        XCTAssertEqual(parsed.code, "abc")
        XCTAssertEqual(parsed.state, "def")
    }

    func testParsePastedCodeRejectsMissingParts() {
        for bad in ["", "nohash", "#stateonly", "codeonly#", "#"] {
            XCTAssertThrowsError(try ClaudeOAuth.parsePastedCode(bad), "should reject \(bad)") { error in
                XCTAssertEqual(error as? OAuthError, .malformedCode)
            }
        }
    }

    // MARK: Request bodies

    func testExchangeBodyFields() throws {
        let body = ClaudeOAuth.exchangeRequestBody(code: "CODE", verifier: "VERIFIER", state: "STATE")
        let fields = try formFields(body)
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertEqual(fields["code"], "CODE")
        XCTAssertEqual(fields["redirect_uri"], "https://platform.claude.com/oauth/code/callback")
        XCTAssertEqual(fields["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(fields["code_verifier"], "VERIFIER")
        XCTAssertEqual(fields["state"], "STATE")
        XCTAssertEqual(fields.count, 6)
    }

    func testRefreshBodyFields() throws {
        let body = ClaudeOAuth.refreshRequestBody(refreshToken: "REFRESH")
        let fields = try formFields(body)
        XCTAssertEqual(fields["grant_type"], "refresh_token")
        XCTAssertEqual(fields["refresh_token"], "REFRESH")
        XCTAssertEqual(fields["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(fields.count, 3)
    }

    func testFormEncodingPercentEncodesReservedCharacters() throws {
        let body = ClaudeOAuth.exchangeRequestBody(code: "a b&c=d+e", verifier: "v", state: "s")
        let raw = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(raw.contains("code=a%20b%26c%3Dd%2Be"), "reserved chars must be percent-encoded, got: \(raw)")
        let fields = try formFields(body)
        XCTAssertEqual(fields["code"], "a b&c=d+e", "round-trip must restore the original value")
    }

    // MARK: Token-response decoding

    func testDecodeTokenResponseFromFixture() throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let creds = try ClaudeOAuth.decodeTokenResponse(fixtureData("oauth_token_sample"), now: now)
        XCTAssertEqual(creds.accessToken, "<test-access-token-1>")
        XCTAssertEqual(creds.refreshToken, "test-refresh-token-1")
        XCTAssertEqual(creds.expiresAt, now.addingTimeInterval(28800))
        XCTAssertEqual(creds.accountEmail, "client@example.com")
    }

    func testDecodeRefreshResponseCarriesCurrentRefreshToken() throws {
        let creds = try ClaudeOAuth.decodeTokenResponse(
            fixtureData("oauth_refresh_sample"),
            now: Date(timeIntervalSince1970: 0),
            currentRefreshToken: "old-refresh-token"
        )
        XCTAssertEqual(creds.accessToken, "<test-access-token-2>")
        XCTAssertEqual(creds.refreshToken, "old-refresh-token",
                       "a refresh response without refresh_token keeps the current one")
        XCTAssertNil(creds.accountEmail)
    }

    func testDecodeWithoutAnyRefreshTokenThrows() throws {
        // No refresh_token in the response and none carried over → unusable.
        XCTAssertThrowsError(
            try ClaudeOAuth.decodeTokenResponse(fixtureData("oauth_refresh_sample"), now: Date())
        ) { error in
            guard case .decoding = error as? OAuthError else {
                return XCTFail("expected OAuthError.decoding, got \(error)")
            }
        }
    }
}
