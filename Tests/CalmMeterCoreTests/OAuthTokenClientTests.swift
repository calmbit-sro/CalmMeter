import XCTest
@testable import CalmMeterCore

/// Status-code mapping of the token endpoint client, via the same stubbed
/// URLSession approach as UsageClientTests. Body/decoding logic is covered by
/// the pure statics in OAuthTests.
final class OAuthTokenClientTests: XCTestCase {
    private func makeClient(status: Int, body: Data = Data()) -> OAuthTokenClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        return OAuthTokenClient(session: URLSession(configuration: config))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testExchangeSuccess() async throws {
        let client = makeClient(status: 200, body: try fixtureData("oauth_token_sample"))
        let creds = try await client.exchange(code: "C", verifier: "V", state: "S")
        XCTAssertEqual(creds.accessToken, "<test-access-token-1>")
        XCTAssertEqual(creds.refreshToken, "test-refresh-token-1")
        XCTAssertEqual(creds.accountEmail, "client@example.com")
    }

    func testExchange400IsInvalidGrant() async throws {
        let client = makeClient(status: 400)
        do {
            _ = try await client.exchange(code: "C", verifier: "V", state: "S")
            XCTFail("expected invalidGrant")
        } catch let e as OAuthError {
            XCTAssertEqual(e, .invalidGrant)
        }
    }

    func testRefresh401IsInvalidGrant() async throws {
        let client = makeClient(status: 401)
        do {
            _ = try await client.refresh(refreshToken: "R")
            XCTFail("expected invalidGrant")
        } catch let e as OAuthError {
            XCTAssertEqual(e, .invalidGrant)
        }
    }

    func testRefreshCarriesOldRefreshTokenWhenOmitted() async throws {
        let client = makeClient(status: 200, body: try fixtureData("oauth_refresh_sample"))
        let creds = try await client.refresh(refreshToken: "old-refresh")
        XCTAssertEqual(creds.accessToken, "<test-access-token-2>")
        XCTAssertEqual(creds.refreshToken, "old-refresh")
    }

    func testServerErrorMapsToHTTP() async throws {
        let client = makeClient(status: 500)
        do {
            _ = try await client.refresh(refreshToken: "R")
            XCTFail("expected http(500)")
        } catch let e as OAuthError {
            XCTAssertEqual(e, .http(500))
        }
    }

    func testOfflineMapsToOffline() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = nil   // protocol fails the load → URLError
        let client = OAuthTokenClient(session: URLSession(configuration: config))
        do {
            _ = try await client.refresh(refreshToken: "R")
            XCTFail("expected offline")
        } catch let e as OAuthError {
            XCTAssertEqual(e, .offline)
        }
    }
}
