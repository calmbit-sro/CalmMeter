import Foundation
import Security

/// The OAuth credentials Claude Code stores in the login keychain under the
/// generic-password service "Claude Code-credentials".
public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum KeychainError: Error, LocalizedError {
    case notFound
    case unexpectedData
    case osStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credentials in the keychain."
        case .unexpectedData:
            return "Credentials have an unexpected format."
        case .osStatus(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return "Keychain error: \(msg)"
        }
    }
}

/// Reads Claude Code's OAuth token from the macOS keychain. Re-reads on every
/// poll so it always picks up the token Claude Code keeps refreshing.
public enum Keychain {
    public static let service = "Claude Code-credentials"

    public static func readCredentials() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        guard let data = item as? Data else { throw KeychainError.unexpectedData }

        return try parse(data)
    }

    /// Parses the `{ "claudeAiOauth": { "accessToken": ... } }` blob.
    /// Split out for unit testing without touching the real keychain.
    public static func parse(_ data: Data) throws -> ClaudeCredentials {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { throw KeychainError.unexpectedData }

        let expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            expiresAt = nil
        }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}
