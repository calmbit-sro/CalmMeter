import Foundation
import Security

/// The OAuth credentials Claude Code stores in the login keychain under the
/// generic-password service "Claude Code-credentials".
public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?
    /// Modification date of the source keychain item when this token was read.
    /// Used to detect when Claude Code rotates the token behind our back.
    public let sourceModified: Date?

    public init(accessToken: String, expiresAt: Date?, subscriptionType: String?, sourceModified: Date? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.sourceModified = sourceModified
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum KeychainError: Error, LocalizedError {
    case notFound
    case unexpectedData
    case osStatus(OSStatus)
    case toolFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credentials in the keychain."
        case .unexpectedData:
            return "Credentials have an unexpected format."
        case .osStatus(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return "Keychain error: \(msg)"
        case .toolFailed(let code):
            return "security tool exited with code \(code)."
        }
    }
}

/// Reads Claude Code's OAuth token from the macOS keychain. Re-reads on every
/// poll so it always picks up the token Claude Code keeps refreshing.
public enum Keychain {
    public static let service = "Claude Code-credentials"

    /// Reads the token (and the item's modification date).
    ///
    /// AIDEV-NOTE: the secret is read via /usr/bin/security, NOT SecItemCopyMatching.
    /// Claude Code rewrites this item with `security add-generic-password -U` on every
    /// token rotation, which resets the item's partition list to ("apple-tool:") and
    /// revokes any "Always Allow" the user granted CalmMeter (proven 2026-08-16).
    /// The `security` binary itself is partition apple-tool:, so reading through it
    /// never hits the XARA partition check → never prompts. Don't revert to SecItem.
    public static func readCredentials() throws -> ClaudeCredentials {
        // Attribute-only query first (never prompts). If a rotation lands between
        // this and the data read, the cached date is older than the item's, so the
        // next poll simply re-reads — silently.
        let mdat = readModificationDate()
        let output = try readSecretViaSecurityTool()
        return try parse(decodeSecurityToolOutput(output), sourceModified: mdat)
    }

    /// Runs `security find-generic-password -s <service> -w` and returns its stdout.
    static func readSecretViaSecurityTool() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        // Discard stderr entirely (exit code carries the outcome). A Pipe here
        // would deadlock if the tool ever wrote >64KB of diagnostics to it.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw KeychainError.toolFailed(-1)
        }
        let data: Data
        do {
            data = try stdout.fileHandleForReading.readToEnd() ?? Data()
        } catch {
            process.waitUntilExit()
            throw KeychainError.toolFailed(-2)
        }
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0: return data
        // 44 is the tool's errSecItemNotFound exit code — unofficial but stable.
        // If Apple ever changes it, notFound degrades to toolFailed (worse
        // message, still a recoverable error).
        case 44: throw KeychainError.notFound
        default: throw KeychainError.toolFailed(process.terminationStatus)
        }
    }

    /// Decodes `security … -w` output: the tool appends a newline, and prints hex
    /// instead of raw bytes when the secret contains non-printable characters. Our
    /// payload is JSON (starts with "{"), which can never be an even-length pure-hex
    /// string, so hex output is unambiguous.
    static func decodeSecurityToolOutput(_ output: Data) -> Data {
        var bytes = [UInt8](output)
        if bytes.last == 0x0A { bytes.removeLast() }

        func hexValue(_ b: UInt8) -> UInt8? {
            switch b {
            case 0x30...0x39: return b - 0x30        // 0-9
            case 0x41...0x46: return b - 0x41 + 10   // A-F
            case 0x61...0x66: return b - 0x61 + 10   // a-f
            default: return nil
            }
        }

        if !bytes.isEmpty, bytes.count.isMultiple(of: 2) {
            var decoded = [UInt8]()
            decoded.reserveCapacity(bytes.count / 2)
            var i = 0
            while i < bytes.count {
                guard let hi = hexValue(bytes[i]), let lo = hexValue(bytes[i + 1]) else {
                    decoded.removeAll()
                    break
                }
                decoded.append(hi << 4 | lo)
                i += 2
            }
            if i == bytes.count { return Data(decoded) }
        }
        return Data(bytes)
    }

    /// Reads only the item's modification date — attribute-only queries do NOT
    /// trigger the keychain prompt, so this is a cheap way to detect rotation.
    /// Returns nil if the item is missing or unreadable.
    public static func readModificationDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let dict = item as? [String: Any] else { return nil }
        return dict[kSecAttrModificationDate as String] as? Date
    }

    /// Parses the `{ "claudeAiOauth": { "accessToken": ... } }` blob.
    /// Split out for unit testing without touching the real keychain.
    public static func parse(_ data: Data, sourceModified: Date? = nil) throws -> ClaudeCredentials {
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
            subscriptionType: oauth["subscriptionType"] as? String,
            sourceModified: sourceModified
        )
    }
}
