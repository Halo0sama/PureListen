import XCTest
import CFNetwork
@testable import PureListenCore

final class NetworkTests: XCTestCase {
    func testSystemAndDirectSessionPolicies() {
        XCTAssertNil(NetworkMode.system.sessionConfiguration().connectionProxyDictionary)
        XCTAssertTrue(NetworkMode.direct.sessionConfiguration().connectionProxyDictionary?.isEmpty == true)
    }

    func testFinderLaunchReadsSystemProxyAndHonorsExceptions() throws {
        let url = URL(string: "https://example.com/")!
        let proxy: [String: Any] = [kCFProxyTypeKey as String: kCFProxyTypeHTTP,
                                   kCFProxyHostNameKey as String: "127.0.0.1",
                                   kCFProxyPortNumberKey as String: 7897]
        XCTAssertEqual(try NetworkMode.system.curlArguments(for: url, environment: [:], proxies: [proxy]),
                       ["--proxy", "http://127.0.0.1:7897"])
        XCTAssertEqual(try NetworkMode.system.curlArguments(for: url, environment: [:], proxies: [
            [kCFProxyTypeKey as String: kCFProxyTypeNone]
        ]), ["--proxy", ""])
        XCTAssertEqual(try NetworkMode.system.curlArguments(for: url, environment: ["HTTPS_PROXY": "http://localhost:7897"], proxies: []), [])
        XCTAssertEqual(try NetworkMode.direct.curlArguments(for: url, environment: ["HTTPS_PROXY": "http://localhost:7897"]),
                       ["--proxy", "", "--noproxy", "*"])
    }

    func testSOCKSAndPACPolicy() throws {
        let url = URL(string: "https://example.com")!
        let socks: [String: Any] = [kCFProxyTypeKey as String: kCFProxyTypeSOCKS,
                                   kCFProxyHostNameKey as String: "127.0.0.1", kCFProxyPortNumberKey as String: 1080]
        XCTAssertEqual(try NetworkMode.system.curlArguments(for: url, environment: [:], proxies: [socks]),
                       ["--proxy", "socks5h://127.0.0.1:1080"])
        XCTAssertThrowsError(try NetworkMode.system.curlArguments(for: url, environment: [:], proxies: [
            [kCFProxyTypeKey as String: kCFProxyTypeAutoConfigurationURL]
        ]))
    }

    func testCurlReportsHTTPFailureAndFollowsRedirects() async throws {
        let fixture = try HTTPFixture { path in
            if path == "/redirect" { return .init(status: 302, headers: ["Location": "/ok"], body: Data()) }
            if path == "/failure" { return .init(status: 503) }
            return .init(headers: ["Set-Cookie": "session=abc=123; Version=1; Path=/"], body: Data("{\"code\":0}".utf8))
        }
        defer { fixture.stop() }
        let response = try await CurlTransport.request(url: fixture.baseURL + "/redirect", mode: .direct)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.effectiveURL, fixture.baseURL + "/ok")
        XCTAssertTrue(response.headers.contains("session=abc=123"))
        do {
            _ = try await CurlTransport.request(url: fixture.baseURL + "/failure", mode: .direct)
            XCTFail("HTTP 503 must throw")
        } catch { XCTAssertEqual((error as NSError).code, 503) }
    }

    func testCurlCancellationTerminatesInFlightRequest() async throws {
        let started = expectation(description: "request reached local server")
        let fixture = try HTTPFixture { _ in started.fulfill(); return .init(delay: 5) }
        defer { fixture.stop() }
        let task = Task { try await CurlTransport.request(url: fixture.baseURL + "/slow", timeout: 10, mode: .direct) }
        await fulfillment(of: [started], timeout: 3)
        let cancelledAt = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request must throw") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 2)
    }

    func testHTTPTaskPreservesVersionedCookieAndManualRedirectResponse() async throws {
        let fixture = try HTTPFixture { path in
            if path == "/redirect" { return .init(status: 302, headers: ["Location": "/cookie"], body: Data()) }
            return .init(headers: ["Set-Cookie": "session=abc=123; Version=1; Path=/"], body: Data("{\"code\":0}".utf8))
        }
        defer { fixture.stop() }
        let response = try await HTTPTask.get(url: fixture.baseURL + "/cookie")
        XCTAssertEqual(response.json["code"] as? Int, 0)
        XCTAssertEqual(response.setCookies["session"], "abc=123")
        let redirect = try await HTTPTask.get(url: fixture.baseURL + "/redirect", followRedirects: false)
        XCTAssertEqual(redirect.statusCode, 302)
    }

    func testCurlTimeoutAndInvalidSchemeThrow() async throws {
        let fixture = try HTTPFixture { _ in .init(delay: 3) }
        defer { fixture.stop() }
        do {
            _ = try await CurlTransport.request(url: fixture.baseURL + "/slow", timeout: 1, mode: .direct)
            XCTFail("Timeout must throw")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        do {
            _ = try await CurlTransport.request(url: "file:///tmp/test", mode: .direct)
            XCTFail("Non HTTP URLs must throw")
        } catch { XCTAssertEqual((error as? URLError)?.code, .badURL) }
    }
}
