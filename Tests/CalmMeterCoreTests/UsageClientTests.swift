import XCTest
@testable import CalmMeterCore

/// Stubs URLSession responses so UsageClient's status-code handling is testable
/// without hitting the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class UsageClientTests: XCTestCase {
    private func makeClient(status: Int, headers: [String: String] = [:], body: Data = Data()) -> UsageClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (resp, body)
        }
        let creds = ClaudeCredentials(accessToken: "test", expiresAt: nil, subscriptionType: nil)
        return UsageClient(session: URLSession(configuration: config), credentialsProvider: { creds })
    }

    func testRateLimitedWithRetryAfter() async {
        let client = makeClient(status: 429, headers: ["Retry-After": "42"])
        do {
            _ = try await client.fetch()
            XCTFail("expected rateLimited")
        } catch let e as UsageClientError {
            XCTAssertEqual(e, .rateLimited(retryAfter: 42))
            XCTAssertEqual(e.retryAfter, 42)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRateLimitedWithoutHeader() async {
        let client = makeClient(status: 429)
        do {
            _ = try await client.fetch()
            XCTFail("expected rateLimited")
        } catch let e as UsageClientError {
            XCTAssertEqual(e, .rateLimited(retryAfter: nil))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testUnauthorized() async {
        let client = makeClient(status: 401)
        do { _ = try await client.fetch(); XCTFail() }
        catch let e as UsageClientError { XCTAssertEqual(e, .unauthorized) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testSuccessDecodes() async throws {
        let json = #"{"five_hour":{"utilization":12.0,"resets_at":null},"seven_day":null,"limits":[],"spend":null}"#
        let client = makeClient(status: 200, body: Data(json.utf8))
        let usage = try await client.fetch()
        XCTAssertEqual(usage.fiveHour?.utilization, 12.0)
    }
}
