import Foundation

/// A language-free classification of why a fetch failed. The UI maps this to a
/// localized message, keeping Core free of display strings.
public enum UsageErrorKind: Equatable, Sendable {
    case offline
    case notLoggedIn            // no credentials anywhere → show the sign-in call to action
    case signedOut              // own-OAuth refresh token rejected → sign in again
    case unauthorized           // token present but rejected
    case credentialsUnreadable  // keychain read/parse failed for another reason
    case rateLimited
    case server(Int)
    case unknown

    public init(_ error: Error) {
        switch error {
        case let e as UsageClientError:
            switch e {
            case .offline: self = .offline
            case .unauthorized: self = .unauthorized
            case .rateLimited: self = .rateLimited
            case .http(let code): self = .server(code)
            case .decoding: self = .unknown
            }
        case let e as KeychainError:
            switch e {
            case .notFound: self = .notLoggedIn
            case .osStatus, .toolFailed, .unexpectedData: self = .credentialsUnreadable
            }
        case let e as OAuthError:
            switch e {
            case .invalidGrant: self = .signedOut
            case .offline: self = .offline
            case .http(let code): self = .server(code)
            case .malformedCode, .stateMismatch, .decoding: self = .unknown
            }
        default:
            self = .unknown
        }
    }
}
