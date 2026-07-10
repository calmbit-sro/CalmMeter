import XCTest
@testable import CalmMeterCore

final class UsageDecodeTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "usage_sample", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testDecodesWindows() throws {
        let usage = try UsageClient.decode(fixtureData())
        XCTAssertEqual(usage.fiveHour?.utilization, 23.0)
        XCTAssertEqual(usage.sevenDay?.utilization, 3.0)
        XCTAssertNotNil(usage.fiveHour?.resetsAt, "resets_at with fractional seconds must parse")
    }

    func testDecodesLimitsAndScope() throws {
        let usage = try UsageClient.decode(fixtureData())
        let limits = try XCTUnwrap(usage.limits)
        XCTAssertEqual(limits.count, 3)

        let session = try XCTUnwrap(limits.first { $0.kind == "session" })
        XCTAssertEqual(session.percent, 23)
        XCTAssertEqual(session.isActive, true)
        XCTAssertEqual(session.severity, .normal)

        let scoped = try XCTUnwrap(limits.first { $0.scope?.model?.displayName != nil })
        XCTAssertEqual(scoped.scope?.model?.displayName, "Fable")
        XCTAssertEqual(scoped.label, "Fable")
    }

    func testOverallSeverityIsWorst() throws {
        let usage = try UsageClient.decode(fixtureData())
        XCTAssertEqual(usage.overallSeverity, .normal)
    }

    func testSpendDecodes() throws {
        let usage = try UsageClient.decode(fixtureData())
        XCTAssertEqual(usage.spend?.used?.amount, 0)
        XCTAssertEqual(usage.spend?.enabled, false)
    }

    func testDateParsingTolerant() {
        XCTAssertNotNil(UsageDate.parse("2026-07-10T09:09:59.686457+00:00"))
        XCTAssertNotNil(UsageDate.parse("2026-07-10T09:09:59+00:00"))
        XCTAssertNil(UsageDate.parse(nil))
        XCTAssertNil(UsageDate.parse(""))
    }

    func testSeverityOrdering() {
        XCTAssertTrue(Severity.normal < Severity.warning)
        XCTAssertTrue(Severity.warning < Severity.critical)
        XCTAssertEqual([Severity.normal, .critical, .warning].max(), .critical)
    }
}

final class KeychainParseTests: XCTestCase {
    func testParsesOAuthBlob() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"abc123","expiresAt":1789000000000,
        "subscriptionType":"max","scopes":["a"]}}
        """.data(using: .utf8)!
        let creds = try Keychain.parse(json)
        XCTAssertEqual(creds.accessToken, "abc123")
        XCTAssertEqual(creds.subscriptionType, "max")
        XCTAssertNotNil(creds.expiresAt)
    }

    func testRejectsMissingToken() {
        let json = #"{"claudeAiOauth":{"refreshToken":"x"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try Keychain.parse(json))
    }
}

final class ResetCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testMinutes() {
        XCTAssertEqual(ResetCountdown.value(until: now.addingTimeInterval(45 * 60), now: now), .minutes(45))
    }
    func testHoursAndMinutes() {
        XCTAssertEqual(ResetCountdown.value(until: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), .hoursMinutes(3, 12))
    }
    func testDays() {
        XCTAssertEqual(ResetCountdown.value(until: now.addingTimeInterval(2 * 86400 + 5 * 3600), now: now), .days(2, 5))
    }
    func testPast() {
        XCTAssertEqual(ResetCountdown.value(until: now.addingTimeInterval(-10), now: now), .now)
    }
    func testNil() {
        XCTAssertNil(ResetCountdown.value(until: nil, now: now))
    }
}
