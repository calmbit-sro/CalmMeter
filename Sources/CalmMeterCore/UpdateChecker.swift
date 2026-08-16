import Foundation

/// A dotted numeric version ("1.0.4", tag-style "v1.0.4"). Missing components
/// compare as zero, so "1.0" == "1.0.0".
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        var s = Substring(string)
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        guard !s.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(part), n >= 0 else { return nil }
            parsed.append(n)
        }
        components = parsed
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

public enum UpdateCheckerError: Error {
    case unexpectedResponse
}

/// The newest published release, as reported by GitHub.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    /// The release page to open in the browser.
    public let url: URL
}

/// Checks GitHub Releases for a newer version. `/releases/latest` never returns
/// drafts or prereleases, so no filtering is needed here. Every failure path
/// returns nil — an update check must never interfere with the app's function.
public struct UpdateChecker: Sendable {
    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/calmbit-sro/CalmMeter/releases/latest")!

    private let fetchData: @Sendable () async throws -> Data

    public init(fetchData: @escaping @Sendable () async throws -> Data = UpdateChecker.fetchLatestRelease) {
        self.fetchData = fetchData
    }

    @Sendable public static func fetchLatestRelease() async throws -> Data {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    /// Decodes the `/releases/latest` response. Split out for fixture testing.
    public static func decode(_ data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let version = AppVersion(payload.tag_name),
              let url = URL(string: payload.html_url) else {
            throw UpdateCheckerError.unexpectedResponse
        }
        return ReleaseInfo(version: version, tagName: payload.tag_name, url: url)
    }

    /// The newest release when it is strictly newer than `currentVersion`, else nil.
    public func check(currentVersion: String) async -> ReleaseInfo? {
        guard let current = AppVersion(currentVersion) else { return nil }
        guard let data = try? await fetchData(),
              let release = try? Self.decode(data) else { return nil }
        return release.version > current ? release : nil
    }
}
