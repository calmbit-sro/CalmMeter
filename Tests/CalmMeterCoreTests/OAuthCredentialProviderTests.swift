import XCTest
@testable import CalmMeterCore

/// In-memory store so provider logic is testable without the real keychain.
final class MemoryOAuthStore: OAuthCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: OAuthCredentials?
    /// When > 0, the next `failNextStores` calls to `store` throw.
    var failNextStores = 0
    /// When > 0, the next `failNextDeletes` calls to `delete` throw.
    var failNextDeletes = 0

    init(_ initial: OAuthCredentials? = nil) { _stored = initial }

    var stored: OAuthCredentials? {
        lock.lock(); defer { lock.unlock() }
        return _stored
    }

    func load() -> OAuthCredentials? { stored }

    func store(_ creds: OAuthCredentials) throws {
        lock.lock(); defer { lock.unlock() }
        if failNextStores > 0 {
            failNextStores -= 1
            throw KeychainError.osStatus(-1)
        }
        _stored = creds
    }

    func delete() throws {
        lock.lock(); defer { lock.unlock() }
        if failNextDeletes > 0 {
            failNextDeletes -= 1
            throw KeychainError.osStatus(-1)
        }
        _stored = nil
    }
}

/// Thread-safe call counter for @Sendable stub closures.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func increment() { lock.lock(); defer { lock.unlock() }; _count += 1 }
}

final class OAuthCredentialProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    private func creds(token: String = "acc", refresh: String = "ref", expiresIn: TimeInterval) -> OAuthCredentials {
        OAuthCredentials(accessToken: token, refreshToken: refresh,
                         expiresAt: now.addingTimeInterval(expiresIn), accountEmail: "a@b.c")
    }

    // MARK: shouldRefresh (pure)

    func testShouldRefreshMargin() {
        XCTAssertFalse(OAuthCredentialProvider.shouldRefresh(expiresAt: now.addingTimeInterval(360), now: now))
        XCTAssertTrue(OAuthCredentialProvider.shouldRefresh(expiresAt: now.addingTimeInterval(240), now: now))
        XCTAssertTrue(OAuthCredentialProvider.shouldRefresh(expiresAt: now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(OAuthCredentialProvider.shouldRefresh(expiresAt: nil, now: now))
    }

    // MARK: provider

    func testServesValidTokenWithoutNetwork() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 3600))
        let refreshes = CallCounter()
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { _ in refreshes.increment(); return self.creds(token: "new", expiresIn: 28800) },
            now: { self.now }
        )
        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "acc")
        XCTAssertEqual(refreshes.count, 0, "a token outside the margin must not hit the network")
    }

    func testRefreshesInsideMarginAndPersistsRotatedRefreshToken() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 60))
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { old in
                XCTAssertEqual(old, "ref")
                return self.creds(token: "new-acc", refresh: "new-ref", expiresIn: 28800)
            },
            now: { self.now }
        )
        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "new-acc")
        XCTAssertEqual(store.stored?.refreshToken, "new-ref",
                       "rotated refresh token must be persisted immediately")
    }

    func testForceRefreshAlwaysRefreshes() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 3600))
        let refreshes = CallCounter()
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { _ in refreshes.increment(); return self.creds(token: "new", expiresIn: 28800) },
            now: { self.now }
        )
        let served = try await provider.credentials(forceRefresh: true)
        XCTAssertEqual(served.accessToken, "new")
        XCTAssertEqual(refreshes.count, 1)
    }

    func testConcurrentCallsSingleFlight() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 60))
        let refreshes = CallCounter()
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { _ in
                refreshes.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                return self.creds(token: "new", expiresIn: 28800)
            },
            now: { self.now }
        )
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await provider.credentials(forceRefresh: false).accessToken }
            }
            for try await token in group { XCTAssertEqual(token, "new") }
        }
        XCTAssertEqual(refreshes.count, 1, "concurrent callers must share one refresh")
    }

    func testInvalidGrantSignsOutAndThrows() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 60))
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { _ in throw OAuthError.invalidGrant },
            now: { self.now }
        )
        do {
            _ = try await provider.credentials(forceRefresh: false)
            XCTFail("expected invalidGrant")
        } catch let e as OAuthError {
            XCTAssertEqual(e, .invalidGrant)
        }
        XCTAssertNil(store.stored, "a rejected refresh token means the sign-in is dead — delete it")
        let has = await provider.hasCredentials()
        XCTAssertFalse(has)
    }

    func testAdoptPersistsAndServes() async throws {
        let store = MemoryOAuthStore()
        let refreshes = CallCounter()
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { _ in refreshes.increment(); return self.creds(token: "x", expiresIn: 28800) },
            now: { self.now }
        )
        let hasBefore = await provider.hasCredentials()
        XCTAssertFalse(hasBefore)

        await provider.adopt(creds(token: "adopted", expiresIn: 28800))
        XCTAssertEqual(store.stored?.accessToken, "adopted")

        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "adopted")
        XCTAssertEqual(refreshes.count, 0)
        let email = await provider.currentAccountEmail()
        XCTAssertEqual(email, "a@b.c")
    }

    func testSignOutDeletesAndThrowsNotFound() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 3600))
        let provider = OAuthCredentialProvider(store: store, refresh: { _ in throw OAuthError.offline }, now: { self.now })
        await provider.signOut()
        XCTAssertNil(store.stored)
        do {
            _ = try await provider.credentials(forceRefresh: false)
            XCTFail("expected notFound")
        } catch let e as KeychainError {
            guard case .notFound = e else { return XCTFail("wrong error: \(e)") }
        }
    }

    func testSignOutSticksWhenDeleteFailsAndRetries() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 3600))
        store.failNextDeletes = 1
        let provider = OAuthCredentialProvider(store: store, refresh: { _ in throw OAuthError.offline }, now: { self.now })

        await provider.signOut()
        XCTAssertNotNil(store.stored, "the failed delete leaves the item behind")

        // Despite the leftover item, the provider must NOT sign the user back in.
        let has = await provider.hasCredentials()
        XCTAssertFalse(has, "signed out must stick even when the keychain delete failed")
        do {
            _ = try await provider.credentials(forceRefresh: false)
            XCTFail("expected notFound")
        } catch let e as KeychainError {
            guard case .notFound = e else { return XCTFail("wrong error: \(e)") }
        }
        XCTAssertNil(store.stored, "the delete must be retried until it lands")
    }

    func testSignInAfterFailedDeleteServesNewCredentials() async throws {
        let store = MemoryOAuthStore(creds(token: "old", expiresIn: 3600))
        store.failNextDeletes = 1
        let provider = OAuthCredentialProvider(store: store, refresh: { _ in throw OAuthError.offline }, now: { self.now })

        await provider.signOut()
        await provider.adopt(creds(token: "readopted", expiresIn: 28800))

        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "readopted",
                       "a fresh sign-in must not be wiped by the pending delete")
        XCTAssertEqual(store.stored?.accessToken, "readopted")
    }

    func testPersistRetriedAfterStoreFailure() async throws {
        let store = MemoryOAuthStore(creds(expiresIn: 60))
        store.failNextStores = 1
        let provider = OAuthCredentialProvider(
            store: store,
            refresh: { _ in self.creds(token: "new", refresh: "new-ref", expiresIn: 28800) },
            now: { self.now }
        )
        // Refresh succeeds but the keychain write fails → degraded: served from memory.
        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "new")
        XCTAssertEqual(store.stored?.refreshToken, "ref", "failed write leaves the old item")

        // Next call retries the persist and heals the store.
        _ = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(store.stored?.refreshToken, "new-ref")
    }
}
