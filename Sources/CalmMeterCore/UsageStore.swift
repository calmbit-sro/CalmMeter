import Foundation
import Combine

/// Observable state for the UI: latest usage, last error, loading flag, and a
/// timer that re-fetches on a configurable interval. `@MainActor` so `@Published`
/// mutations are always delivered on the main thread.
@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var usage: Usage?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastUpdated: Date?

    private let client: UsageClient
    private var timer: Timer?
    private var interval: TimeInterval

    public init(client: UsageClient = UsageClient(), interval: TimeInterval = 60) {
        self.client = client
        self.interval = interval
    }

    /// Begin polling. Fires immediately, then every `interval` seconds.
    public func start() {
        scheduleTimer()
        Task { await refreshNow() }
    }

    /// Change the poll cadence at runtime (from Preferences).
    public func setInterval(_ seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        scheduleTimer()
    }

    public func refreshNow() async {
        isLoading = true
        defer { isLoading = false }
        do {
            usage = try await client.fetch()
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }
}
