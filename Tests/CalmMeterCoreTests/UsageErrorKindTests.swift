import XCTest
@testable import CalmMeterCore

final class UsageErrorKindTests: XCTestCase {
    func testNotFoundIsNotLoggedIn() {
        XCTAssertEqual(UsageErrorKind(KeychainError.notFound), .notLoggedIn)
    }

    func testKeychainFailuresAreNotSessionExpired() {
        // A user who never installed Claude Code but hits an odd keychain
        // failure must not be told their session expired.
        XCTAssertEqual(UsageErrorKind(KeychainError.toolFailed(1)), .credentialsUnreadable)
        XCTAssertEqual(UsageErrorKind(KeychainError.osStatus(-25300)), .credentialsUnreadable)
        XCTAssertEqual(UsageErrorKind(KeychainError.unexpectedData), .credentialsUnreadable)
    }

    func testInvalidGrantIsSignedOut() {
        XCTAssertEqual(UsageErrorKind(OAuthError.invalidGrant), .signedOut)
    }

    func testOtherOAuthErrors() {
        XCTAssertEqual(UsageErrorKind(OAuthError.offline), .offline)
        XCTAssertEqual(UsageErrorKind(OAuthError.http(503)), .server(503))
        XCTAssertEqual(UsageErrorKind(OAuthError.decoding("x")), .unknown)
    }

    func testTransportErrorsUnchanged() {
        XCTAssertEqual(UsageErrorKind(UsageClientError.offline), .offline)
        XCTAssertEqual(UsageErrorKind(UsageClientError.unauthorized), .unauthorized)
        XCTAssertEqual(UsageErrorKind(UsageClientError.rateLimited(retryAfter: nil)), .rateLimited)
        XCTAssertEqual(UsageErrorKind(UsageClientError.http(500)), .server(500))
    }
}
