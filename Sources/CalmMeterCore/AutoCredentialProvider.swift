import Foundation

/// Routes between the two credential sources: CalmMeter's own OAuth sign-in
/// (preferred) and Claude Code's keychain item (zero-config fallback).
///
/// AIDEV-NOTE: own-OAuth is checked FIRST — its existence check is a SecItem
/// read on an item this app owns (never prompts, never spawns a subprocess).
/// The Claude Code path (mdat query / `security` spawn) runs only when own
/// credentials are absent. This preserves the never-prompt polling invariant.
/// The check happens per call, so signing in/out switches the source at the
/// next poll without rebuilding UsageStore.
public struct AutoCredentialProvider: CredentialProviding {
    private let oauth: OAuthCredentialProvider
    private let claudeCode: CredentialProviding

    public init(oauth: OAuthCredentialProvider, claudeCode: CredentialProviding = CachedCredentialProvider()) {
        self.oauth = oauth
        self.claudeCode = claudeCode
    }

    public func credentials(forceRefresh: Bool) async throws -> ClaudeCredentials {
        if await oauth.hasCredentials() {
            return try await oauth.credentials(forceRefresh: forceRefresh)
        }
        return try await claudeCode.credentials(forceRefresh: forceRefresh)
    }
}
