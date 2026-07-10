import Foundation

/// A language-free classification of why a fetch failed. The UI maps this to a
/// localized message, keeping Core free of display strings.
public enum UsageErrorKind: Equatable, Sendable {
    case offline
    case notLoggedIn        // no Claude Code credentials in the keychain
    case unauthorized       // token present but rejected
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
            default: self = .unauthorized
            }
        default:
            self = .unknown
        }
    }
}
