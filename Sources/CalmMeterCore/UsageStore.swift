import Foundation
import Combine

/// Observable state for the UI: latest usage, last error, loading flag, and a
/// self-scheduling poll loop with backoff. `@MainActor` so `@Published`
/// mutations are always delivered on the main thread.
///
/// Scheduling is one-shot (not a repeating timer): after every attempt we decide
/// when to try again. On success we wait the normal `interval`; on failure we
/// back off (respecting `Retry-After` for 429s) so we never hammer a server
/// that's already pushing back. The last good `usage` is kept across errors.
@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var usage: Usage?
    @Published public private(set) var lastError: UsageErrorKind?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastUpdated: Date?

    private let client: UsageClient
    private var interval: TimeInterval
    private var timer: Timer?
    private var consecutiveFailures = 0
    private var started = false

    /// Backoff ceiling — never wait longer than this between attempts.
    private let maxBackoff: TimeInterval = 15 * 60

    public init(client: UsageClient = UsageClient(), interval: TimeInterval = 60) {
        self.client = client
        self.interval = interval
    }

    /// Idempotent: safe to call more than once — only the first call starts the
    /// poll loop, so we never end up with two concurrent loops double-polling.
    public func start() {
        guard !started else { return }
        started = true
        Task { await refreshNow() }
    }

    /// Change the poll cadence at runtime (from Preferences). Takes effect on the
    /// next scheduled poll; also reschedules the pending one.
    public func setInterval(_ seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        if consecutiveFailures == 0 { scheduleNext(after: interval) }
    }

    /// Fetch once and (re)schedule the next poll based on the outcome.
    public func refreshNow() async {
        isLoading = true
        var nextDelay = interval
        do {
            usage = try await client.fetch()
            lastUpdated = Date()
            lastError = nil
            consecutiveFailures = 0
            nextDelay = interval
        } catch {
            consecutiveFailures += 1
            lastError = UsageErrorKind(error)
            nextDelay = backoffDelay(for: error)
        }
        isLoading = false
        scheduleNext(after: nextDelay)
    }

    /// Exponential backoff, honouring a server-provided `Retry-After` for 429s.
    private func backoffDelay(for error: Error) -> TimeInterval {
        if let retryAfter = (error as? UsageClientError)?.retryAfter {
            return min(max(TimeInterval(retryAfter), interval), maxBackoff)
        }
        let exponential = interval * pow(2, Double(consecutiveFailures - 1))
        return min(exponential, maxBackoff)
    }

    private func scheduleNext(after delay: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }
}
