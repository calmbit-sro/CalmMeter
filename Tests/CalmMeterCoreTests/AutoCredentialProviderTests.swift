import XCTest
@testable import CalmMeterCore

final class AutoCredentialProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    private func oauthCreds(token: String) -> OAuthCredentials {
        OAuthCredentials(accessToken: token, refreshToken: "ref",
                         expiresAt: now.addingTimeInterval(28800), accountEmail: nil)
    }

    private func makeProviders(oauthStore: MemoryOAuthStore) -> (AutoCredentialProvider, CallCounter) {
        let claudeCodeReads = CallCounter()
        let oauth = OAuthCredentialProvider(
            store: oauthStore,
            refresh: { _ in throw OAuthError.offline },
            now: { self.now }
        )
        let claudeCode = AnyCredentialProvider { _ in
            claudeCodeReads.increment()
            return ClaudeCredentials(accessToken: "<claude-code-token>", expiresAt: nil, subscriptionType: nil)
        }
        return (AutoCredentialProvider(oauth: oauth, claudeCode: claudeCode), claudeCodeReads)
    }

    func testPrefersOwnOAuthAndNeverTouchesClaudeCode() async throws {
        let store = MemoryOAuthStore(oauthCreds(token: "own"))
        let (provider, claudeCodeReads) = makeProviders(oauthStore: store)
        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "own")
        XCTAssertEqual(claudeCodeReads.count, 0,
                       "with own credentials the Claude Code path must not run (never-prompt invariant)")
    }

    func testFallsBackToClaudeCodeWhenNoOwnCredentials() async throws {
        let (provider, claudeCodeReads) = makeProviders(oauthStore: MemoryOAuthStore())
        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "<claude-code-token>")
        XCTAssertEqual(claudeCodeReads.count, 1)
    }

    func testSignInSwitchesSourceWithoutRebuild() async throws {
        let store = MemoryOAuthStore()
        let oauth = OAuthCredentialProvider(store: store, refresh: { _ in throw OAuthError.offline }, now: { self.now })
        let claudeCode = AnyCredentialProvider { _ in
            ClaudeCredentials(accessToken: "<claude-code-token>", expiresAt: nil, subscriptionType: nil)
        }
        let provider = AutoCredentialProvider(oauth: oauth, claudeCode: claudeCode)

        let before = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(before.accessToken, "<claude-code-token>")

        await oauth.adopt(oauthCreds(token: "own"))
        let after = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(after.accessToken, "own", "sign-in must take effect on the next call")

        await oauth.signOut()
        let signedOut = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(signedOut.accessToken, "<claude-code-token>", "sign-out must fall back")
    }
}
