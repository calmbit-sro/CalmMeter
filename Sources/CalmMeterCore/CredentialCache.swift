import Foundation
import Security

/// Supplies an access token, hiding *where* it comes from.
public protocol CredentialProviding {
    /// - Parameter forceRefresh: when true, bypass any cache and re-read the
    ///   source of truth (Claude Code's keychain item), which may prompt.
    func credentials(forceRefresh: Bool) throws -> ClaudeCredentials
}

/// Test/utility provider backed by a closure.
public struct AnyCredentialProvider: CredentialProviding {
    private let body: (Bool) throws -> ClaudeCredentials
    public init(_ body: @escaping (Bool) throws -> ClaudeCredentials) { self.body = body }
    public func credentials(forceRefresh: Bool) throws -> ClaudeCredentials {
        try body(forceRefresh)
    }
}

/// Local, non-prompting store for a cached copy of the token.
public protocol CredentialCaching {
    func load() -> ClaudeCredentials?
    func store(_ creds: ClaudeCredentials) throws
}

/// Reads Claude Code's token once, then serves it from CalmMeter's *own* keychain
/// item so we don't prompt on every launch/poll.
///
/// macOS won't persistently grant a third-party app access to another app's
/// keychain item (the "Always Allow" doesn't stick for partition-listed items),
/// so every read of `Claude Code-credentials` risks a password prompt. By copying
/// the token into an item CalmMeter owns, subsequent reads never prompt. We only
/// go back to Claude Code's item when the cached token stops working (HTTP 401),
/// i.e. roughly once per token rotation.
public struct CachedCredentialProvider: CredentialProviding {
    private let cache: CredentialCaching
    private let readSourceOfTruth: () throws -> ClaudeCredentials

    public init(
        cache: CredentialCaching = CredentialCache(),
        readSourceOfTruth: @escaping () throws -> ClaudeCredentials = Keychain.readCredentials
    ) {
        self.cache = cache
        self.readSourceOfTruth = readSourceOfTruth
    }

    public func credentials(forceRefresh: Bool) throws -> ClaudeCredentials {
        if !forceRefresh, let cached = cache.load() {
            return cached
        }
        // Bootstrap or refresh: read Claude Code's item (may prompt) and cache it.
        let fresh = try readSourceOfTruth()
        try? cache.store(fresh)
        return fresh
    }
}

/// CalmMeter's own generic-password keychain item holding a copy of the token.
/// Owned by this app, so reads/writes never prompt.
public struct CredentialCache: CredentialCaching {
    public static let service = "com.calmbit.CalmMeter.credentials"
    public static let account = "claudeAiOauth"

    public init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func load() -> ClaudeCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? decode(data)
    }

    public func store(_ creds: ClaudeCredentials) throws {
        let data = try encode(creds)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.osStatus(status)
        }
    }

    // MARK: serialization

    private struct Stored: Codable {
        let accessToken: String
        let expiresAtMillis: Double?
        let subscriptionType: String?
    }

    func encode(_ creds: ClaudeCredentials) throws -> Data {
        let stored = Stored(
            accessToken: creds.accessToken,
            expiresAtMillis: creds.expiresAt.map { $0.timeIntervalSince1970 * 1000 },
            subscriptionType: creds.subscriptionType
        )
        return try JSONEncoder().encode(stored)
    }

    func decode(_ data: Data) throws -> ClaudeCredentials {
        let s = try JSONDecoder().decode(Stored.self, from: data)
        return ClaudeCredentials(
            accessToken: s.accessToken,
            expiresAt: s.expiresAtMillis.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: s.subscriptionType
        )
    }
}
