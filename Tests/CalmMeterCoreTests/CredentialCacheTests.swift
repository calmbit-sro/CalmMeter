import XCTest
@testable import CalmMeterCore

/// In-memory cache so we can test the provider logic without the real keychain.
final class MemoryCache: CredentialCaching, @unchecked Sendable {
    var stored: ClaudeCredentials?
    private(set) var storeCount = 0
    func load() -> ClaudeCredentials? { stored }
    func store(_ creds: ClaudeCredentials) throws { stored = creds; storeCount += 1 }
}

final class CredentialCacheTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let cache = CredentialCache()
        let creds = ClaudeCredentials(
            accessToken: "tok",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            subscriptionType: "max",
            sourceModified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let restored = try cache.decode(cache.encode(creds))
        XCTAssertEqual(restored.accessToken, "tok")
        XCTAssertEqual(restored.subscriptionType, "max")
        XCTAssertEqual(restored.expiresAt, creds.expiresAt)
        XCTAssertEqual(restored.sourceModified, creds.sourceModified)
    }

    func testProviderReadsSourceOnceThenServesCache() async throws {
        let cache = MemoryCache()
        var sourceReads = 0
        // Fixed source date → not rotated → cache is served.
        let provider = CachedCredentialProvider(
            cache: cache,
            readSourceOfTruth: {
                sourceReads += 1
                return ClaudeCredentials(accessToken: "fresh-\(sourceReads)", expiresAt: nil,
                                         subscriptionType: nil, sourceModified: Date(timeIntervalSince1970: 100))
            },
            sourceModifiedDate: { Date(timeIntervalSince1970: 100) }
        )

        let first = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(first.accessToken, "fresh-1")
        XCTAssertEqual(sourceReads, 1)
        XCTAssertEqual(cache.storeCount, 1)

        // Served from cache — no source read (no keychain prompt).
        let second = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(second.accessToken, "fresh-1")
        XCTAssertEqual(sourceReads, 1)

        // forceRefresh re-reads the source regardless.
        let refreshed = try await provider.credentials(forceRefresh: true)
        XCTAssertEqual(refreshed.accessToken, "fresh-2")
        XCTAssertEqual(sourceReads, 2)
    }

    func testProviderRefetchesWhenSourceRotates() async throws {
        let cache = MemoryCache()
        var sourceReads = 0
        var currentDate = Date(timeIntervalSince1970: 100)  // source item mdat
        let provider = CachedCredentialProvider(
            cache: cache,
            readSourceOfTruth: {
                sourceReads += 1
                return ClaudeCredentials(accessToken: "tok-\(sourceReads)", expiresAt: nil,
                                         subscriptionType: nil, sourceModified: currentDate)
            },
            sourceModifiedDate: { currentDate }
        )

        let first = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(first.accessToken, "tok-1")
        let cached = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(cached.accessToken, "tok-1") // cached
        XCTAssertEqual(sourceReads, 1)

        // Claude Code rotates the token → item modification date changes.
        currentDate = Date(timeIntervalSince1970: 200)
        let rotated = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(rotated.accessToken, "tok-2",
                       "must pick up the rotated token without an auth failure")
        XCTAssertEqual(sourceReads, 2)
    }

    func testProviderKeepsCacheWhenDateUnreadable() async throws {
        let cache = MemoryCache()
        cache.stored = ClaudeCredentials(accessToken: "cached", expiresAt: nil,
                                         subscriptionType: nil, sourceModified: Date(timeIntervalSince1970: 100))
        var sourceReads = 0
        let provider = CachedCredentialProvider(
            cache: cache,
            readSourceOfTruth: { sourceReads += 1; return ClaudeCredentials(accessToken: "x", expiresAt: nil, subscriptionType: nil) },
            sourceModifiedDate: { nil }  // can't read date → don't risk a prompt
        )
        let served = try await provider.credentials(forceRefresh: false)
        XCTAssertEqual(served.accessToken, "cached")
        XCTAssertEqual(sourceReads, 0)
    }
}
