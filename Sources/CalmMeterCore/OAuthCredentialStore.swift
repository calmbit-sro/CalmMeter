import Foundation
import Security

/// Persistence for the credentials CalmMeter minted itself.
public protocol OAuthCredentialStoring: Sendable {
    func load() -> OAuthCredentials?
    func store(_ creds: OAuthCredentials) throws
    func delete() throws
}

/// CalmMeter's own generic-password keychain item holding the self-minted OAuth
/// credentials. Deliberately separate from `CredentialCache` (the mirror of
/// Claude Code's token): that item is a cache with mod-date invalidation, this
/// one is the authoritative source holding a refresh token that must never be
/// dropped by cache semantics. Owned by this app, so reads/writes never prompt.
public struct OAuthCredentialStore: OAuthCredentialStoring {
    public static let service = "com.calmbit.CalmMeter.oauth"
    public static let account = "oauth"

    public init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func load() -> OAuthCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? decode(data)
    }

    public func store(_ creds: OAuthCredentials) throws {
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

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    // MARK: serialization

    private struct Stored: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAtMillis: Double
        let accountEmail: String?
    }

    func encode(_ creds: OAuthCredentials) throws -> Data {
        let stored = Stored(
            accessToken: creds.accessToken,
            refreshToken: creds.refreshToken,
            expiresAtMillis: creds.expiresAt.timeIntervalSince1970 * 1000,
            accountEmail: creds.accountEmail
        )
        return try JSONEncoder().encode(stored)
    }

    func decode(_ data: Data) throws -> OAuthCredentials {
        let s = try JSONDecoder().decode(Stored.self, from: data)
        return OAuthCredentials(
            accessToken: s.accessToken,
            refreshToken: s.refreshToken,
            expiresAt: Date(timeIntervalSince1970: s.expiresAtMillis / 1000),
            accountEmail: s.accountEmail
        )
    }
}
