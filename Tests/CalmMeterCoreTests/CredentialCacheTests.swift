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
            subscriptionType: "max"
        )
        let restored = try cache.decode(cache.encode(creds))
        XCTAssertEqual(restored.accessToken, "tok")
        XCTAssertEqual(restored.subscriptionType, "max")
        XCTAssertEqual(restored.expiresAt, creds.expiresAt)
    }

    func testProviderReadsSourceOnceThenServesCache() throws {
        let cache = MemoryCache()
        var sourceReads = 0
        let provider = CachedCredentialProvider(cache: cache) {
            sourceReads += 1
            return ClaudeCredentials(accessToken: "fresh-\(sourceReads)", expiresAt: nil, subscriptionType: nil)
        }

        // First read bootstraps from source and caches.
        let first = try provider.credentials(forceRefresh: false)
        XCTAssertEqual(first.accessToken, "fresh-1")
        XCTAssertEqual(sourceReads, 1)
        XCTAssertEqual(cache.storeCount, 1)

        // Second read is served from cache — no source hit (no keychain prompt).
        let second = try provider.credentials(forceRefresh: false)
        XCTAssertEqual(second.accessToken, "fresh-1")
        XCTAssertEqual(sourceReads, 1)

        // forceRefresh (after a 401) re-reads the source and re-caches.
        let refreshed = try provider.credentials(forceRefresh: true)
        XCTAssertEqual(refreshed.accessToken, "fresh-2")
        XCTAssertEqual(sourceReads, 2)
        XCTAssertEqual(cache.storeCount, 2)
    }
}
