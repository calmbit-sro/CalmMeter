import Foundation

/// Serves the credentials CalmMeter minted itself and keeps them fresh: checks
/// expiry before every use and calls the token endpoint when needed. An actor,
/// so refreshes are serialized; `refreshTask` additionally single-flights them
/// (concurrent callers await the one in-progress refresh instead of stacking).
public actor OAuthCredentialProvider: CredentialProviding {
    private let store: OAuthCredentialStoring
    private let refresh: @Sendable (String) async throws -> OAuthCredentials
    private let now: @Sendable () -> Date

    private var current: OAuthCredentials?
    /// Credentials that failed to persist — kept so the write can be retried.
    private var pendingStore: OAuthCredentials?
    /// A sign-out whose keychain delete failed — the leftover item must NOT
    /// sign the user back in; the delete is retried until it lands.
    private var pendingDelete = false
    private var refreshTask: Task<OAuthCredentials, Error>?

    public init(
        store: OAuthCredentialStoring = OAuthCredentialStore(),
        refresh: @escaping @Sendable (String) async throws -> OAuthCredentials
            = { try await OAuthTokenClient().refresh(refreshToken: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.refresh = refresh
        self.now = now
    }

    /// True refresh-decision margin: renew while the token still has less than
    /// this much life left, so a poll never goes out with a dying token.
    public static func shouldRefresh(expiresAt: Date?, now: Date, margin: TimeInterval = 300) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) < margin
    }

    public func hasCredentials() -> Bool { loaded() != nil }

    public func currentAccountEmail() -> String? { loaded()?.accountEmail }

    /// Called after a successful sign-in exchange: hold + persist.
    public func adopt(_ creds: OAuthCredentials) {
        pendingDelete = false   // a fresh sign-in supersedes any unfinished sign-out
        current = creds
        persist(creds)
    }

    public func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        current = nil
        pendingStore = nil
        deleteFromStore()
    }

    public func credentials(forceRefresh: Bool) async throws -> ClaudeCredentials {
        if let pending = pendingStore { persist(pending) }
        guard let creds = loaded() else { throw KeychainError.notFound }

        let fresh: OAuthCredentials
        if forceRefresh || Self.shouldRefresh(expiresAt: creds.expiresAt, now: now()) {
            fresh = try await refreshed(creds)
        } else {
            fresh = creds
        }
        return ClaudeCredentials(accessToken: fresh.accessToken, expiresAt: fresh.expiresAt,
                                 subscriptionType: nil)
    }

    private func loaded() -> OAuthCredentials? {
        if pendingDelete {
            deleteFromStore()
            return nil
        }
        if let current { return current }
        current = store.load()
        return current
    }

    private func deleteFromStore() {
        do {
            try store.delete()
            pendingDelete = false
        } catch {
            pendingDelete = true
        }
    }

    private func refreshed(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        if let task = refreshTask { return try await task.value }

        let refresh = refresh
        let task = Task { try await refresh(creds.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            current = fresh
            // AIDEV-NOTE: refresh tokens rotate — persist the NEW one before the
            // fresh access token is first used; losing it strands the user
            // signed-out after the 8h access-token expiry.
            persist(fresh)
            return fresh
        } catch OAuthError.invalidGrant {
            // The refresh token is dead (revoked/used elsewhere) — this sign-in
            // cannot recover. Drop it so the UI shows the sign-in call to action.
            signOut()
            throw OAuthError.invalidGrant
        }
    }

    private func persist(_ creds: OAuthCredentials) {
        do {
            try store.store(creds)
            pendingStore = nil
        } catch {
            // Degraded, not fatal: keep serving from memory and retry the write
            // on the next credentials() call.
            pendingStore = creds
        }
    }
}
