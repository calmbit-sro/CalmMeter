import XCTest
@testable import CalmMeterCore

final class OAuthCredentialStoreTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let store = OAuthCredentialStore()
        let creds = OAuthCredentials(
            accessToken: "acc-tok",
            refreshToken: "ref-tok",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountEmail: "client@example.com"
        )
        let restored = try store.decode(store.encode(creds))
        XCTAssertEqual(restored, creds)
    }

    func testDecodeWithoutEmail() throws {
        let store = OAuthCredentialStore()
        let creds = OAuthCredentials(
            accessToken: "acc-tok",
            refreshToken: "ref-tok",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountEmail: nil
        )
        let restored = try store.decode(store.encode(creds))
        XCTAssertNil(restored.accountEmail)
        XCTAssertEqual(restored, creds)
    }
}
