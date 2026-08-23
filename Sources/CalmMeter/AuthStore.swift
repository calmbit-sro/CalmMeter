import Foundation
import Combine
import CalmMeterCore

/// UI-facing state for the own-OAuth sign-in. Thin orchestration only — URL
/// building, parsing, state validation and token exchange live in Core.
@MainActor
final class AuthStore: ObservableObject {
    /// Non-nil ⇔ signed in via CalmMeter's own OAuth credentials.
    @Published private(set) var accountEmail: String?

    private let oauth: OAuthCredentialProvider
    private let tokenClient: OAuthTokenClient

    init(oauth: OAuthCredentialProvider, tokenClient: OAuthTokenClient = OAuthTokenClient()) {
        self.oauth = oauth
        self.tokenClient = tokenClient
    }

    /// Reflect the persisted state on launch.
    func loadCurrentAccount() async {
        guard await oauth.hasCredentials() else { return }
        accountEmail = await oauth.currentAccountEmail() ?? ""
    }

    /// Completes the manual-paste sign-in: validates `CODE#STATE` against this
    /// attempt's PKCE material, exchanges the code, and adopts the credentials.
    func completeSignIn(pasted: String, pkce: PKCE) async throws {
        let (code, state) = try ClaudeOAuth.parsePastedCode(pasted)
        guard state == pkce.state else { throw OAuthError.stateMismatch }
        let creds = try await tokenClient.exchange(code: code, verifier: pkce.verifier, state: state)
        await oauth.adopt(creds)
        accountEmail = creds.accountEmail ?? ""
    }

    func signOut() async {
        await oauth.signOut()
        accountEmail = nil
    }
}
