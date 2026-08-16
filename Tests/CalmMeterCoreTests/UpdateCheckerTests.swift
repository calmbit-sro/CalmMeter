import XCTest
@testable import CalmMeterCore

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndVPrefixedVersions() {
        XCTAssertEqual(AppVersion("1.0.4")?.components, [1, 0, 4])
        XCTAssertEqual(AppVersion("v1.0.5")?.components, [1, 0, 5])
    }

    func testRejectsUnparseableVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1.x.2"))
    }

    func testComparesNumericallyPerComponent() {
        XCTAssertTrue(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        XCTAssertTrue(AppVersion("1.1.0")! > AppVersion("1.0.99")!)
        XCTAssertTrue(AppVersion("2.0")! > AppVersion("1.9.9")!)
        XCTAssertFalse(AppVersion("1.0.4")! > AppVersion("1.0.4")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertTrue(AppVersion("1.0.1")! > AppVersion("1.0")!)
    }
}

final class UpdateCheckerTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "github_release_sample", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testDecodesLatestReleaseResponse() throws {
        let release = try UpdateChecker.decode(fixtureData())
        XCTAssertEqual(release.tagName, "v1.0.5")
        XCTAssertEqual(release.version, AppVersion("1.0.5"))
        XCTAssertEqual(release.url.absoluteString, "https://github.com/calmbit-sro/CalmMeter/releases/tag/v1.0.5")
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try UpdateChecker.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try UpdateChecker.decode(Data("{\"tag_name\":\"nonsense\"}".utf8)))
    }

    func testCheckReturnsReleaseWhenRemoteIsNewer() async throws {
        let data = try fixtureData()
        let checker = UpdateChecker(fetchData: { data })
        let release = await checker.check(currentVersion: "1.0.4")
        XCTAssertEqual(release?.tagName, "v1.0.5")
    }

    func testCheckReturnsNilWhenUpToDateOrAhead() async throws {
        let data = try fixtureData()
        let checker = UpdateChecker(fetchData: { data })
        let same = await checker.check(currentVersion: "1.0.5")
        XCTAssertNil(same)
        let ahead = await checker.check(currentVersion: "9.9.9")
        XCTAssertNil(ahead)
    }

    func testCheckReturnsNilOnFetchErrorOrGarbage() async {
        struct Boom: Error {}
        let failing = UpdateChecker(fetchData: { throw Boom() })
        let fromError = await failing.check(currentVersion: "1.0.4")
        XCTAssertNil(fromError)

        let garbage = UpdateChecker(fetchData: { Data("[]".utf8) })
        let fromGarbage = await garbage.check(currentVersion: "1.0.4")
        XCTAssertNil(fromGarbage)
    }

    func testCheckReturnsNilForUnparseableCurrentVersion() async throws {
        let data = try fixtureData()
        let checker = UpdateChecker(fetchData: { data })
        let release = await checker.check(currentVersion: "?")
        XCTAssertNil(release)
    }
}
