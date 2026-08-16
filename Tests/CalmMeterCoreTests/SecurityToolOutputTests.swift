import XCTest
@testable import CalmMeterCore

/// `security find-generic-password -w` prints the secret followed by a newline,
/// and switches to hex when the secret contains non-printable bytes. These tests
/// pin the decoding of that output without spawning the real tool.
final class SecurityToolOutputTests: XCTestCase {
    private let json = #"{"claudeAiOauth":{"accessToken":"tok"}}"#

    func testDecodeStripsSingleTrailingNewline() {
        let output = Data((json + "\n").utf8)
        XCTAssertEqual(Keychain.decodeSecurityToolOutput(output), Data(json.utf8))
    }

    func testDecodePassesThroughOutputWithoutNewline() {
        let output = Data(json.utf8)
        XCTAssertEqual(Keychain.decodeSecurityToolOutput(output), Data(json.utf8))
    }

    func testDecodeLowercaseHexOutput() {
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        let output = Data((hex + "\n").utf8)
        XCTAssertEqual(Keychain.decodeSecurityToolOutput(output), Data(json.utf8))
    }

    func testDecodeUppercaseHexOutput() {
        let hex = Data(json.utf8).map { String(format: "%02X", $0) }.joined()
        let output = Data(hex.utf8)
        XCTAssertEqual(Keychain.decodeSecurityToolOutput(output), Data(json.utf8))
    }

    func testDecodeLeavesOddLengthHexLookalikeRaw() {
        // A raw secret that merely looks hex-ish but has odd length must not be decoded.
        let output = Data("abc\n".utf8)
        XCTAssertEqual(Keychain.decodeSecurityToolOutput(output), Data("abc".utf8))
    }

    func testDecodeEmptyOutputStaysEmpty() {
        XCTAssertEqual(Keychain.decodeSecurityToolOutput(Data("\n".utf8)), Data())
    }
}
