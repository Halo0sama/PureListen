import XCTest
@testable import PureListenCore

final class DownloaderTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = URLSession(configuration: NetworkMode.direct.sessionConfiguration())
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        try FileManager.default.removeItem(at: directory)
    }

    private func download(_ url: String) async throws -> URL {
        try await Downloader.ensureLocal(url: url, key: "same-name", format: "flac",
                                         directory: directory, session: session)
    }

    func testSameNamedFilesAndAccountsDoNotShareCache() {
        func filename(_ url: String, headers: [String: String] = [:]) -> String {
            Downloader.cacheFilename(url: url, key: "song", format: "flac", headers: headers)
        }
        XCTAssertNotEqual(filename("https://a.example/song.flac"), filename("https://b.example/song.flac"))
        XCTAssertNotEqual(filename("https://a.example/song.flac?q=1"), filename("https://a.example/song.flac?q=2"))
        XCTAssertNotEqual(filename("https://a.example/song.flac", headers: ["Cookie": "account=a"]),
                          filename("https://a.example/song.flac", headers: ["Cookie": "account=b"]))
        let unsafe = Downloader.cacheFilename(url: "https://example.com/song", key: "../../outside", format: "../../file", headers: [:])
        XCTAssertFalse(unsafe.contains("/"))
        XCTAssertTrue(unsafe.hasSuffix(".audio"))
    }

    func testSuccessfulDownloadAndCacheHit() async throws {
        let fixture = try HTTPFixture { _ in .init() }
        let url = fixture.baseURL + "/song.flac"
        let first = try await download(url)
        XCTAssertEqual(try Data(contentsOf: first), Data(repeating: 42, count: 8192))
        fixture.stop()
        // 服务已停止，第二次只能从完整缓存读取。
        let cached = try await download(url)
        XCTAssertEqual(first, cached)
    }

    func testConcurrentDownloadsPublishOneCompleteFile() async throws {
        let fixture = try HTTPFixture { _ in .init() }
        defer { fixture.stop() }
        async let a = download(fixture.baseURL + "/same.flac")
        async let b = download(fixture.baseURL + "/same.flac")
        let (first, second) = try await (a, b)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first).count, 8192)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testInvalidHTTPContentAndPlaceholdersAreNotCached() async throws {
        let fixture = try HTTPFixture { path in
            switch path {
            case "/error": return .init(status: 403)
            case "/html": return .init(headers: ["Content-Type": "text/html"])
            case "/json": return .init(headers: ["Content-Type": "application/json"])
            default: return .init(body: Data(repeating: 1, count: 32))
            }
        }
        defer { fixture.stop() }
        for path in ["/error", "/html", "/json", "/tiny"] {
            do { _ = try await download(fixture.baseURL + path); XCTFail("Invalid content must fail: \(path)") }
            catch { /* Expected. */ }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testTruncatedExistingCacheIsReplaced() async throws {
        let fixture = try HTTPFixture { _ in .init() }
        defer { fixture.stop() }
        let url = fixture.baseURL + "/song.flac"
        let destination = directory.appendingPathComponent(Downloader.cacheFilename(url: url, key: "same-name", format: "flac", headers: [:]))
        try Data([1, 2, 3]).write(to: destination)
        let result = try await download(url)
        XCTAssertEqual(try Data(contentsOf: result).count, 8192)
    }

    func testCancellationLeavesNoCacheFile() async throws {
        let started = expectation(description: "download started")
        let fixture = try HTTPFixture { _ in started.fulfill(); return .init(delay: 5) }
        defer { fixture.stop() }
        let task = Task { try await download(fixture.baseURL + "/slow.flac") }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled download must fail") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testCommitFailureDoesNotReturnMissingFile() async throws {
        let filenameURL = "placeholder"
        var destination: URL!
        let fixture = try HTTPFixture { _ in
            // 模拟下载期间目录被占用，发布失败不能伪装成成功。
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try? Data([1]).write(to: destination.appendingPathComponent("occupied"))
            return .init()
        }
        defer { fixture.stop() }
        let url = fixture.baseURL + "/" + filenameURL
        destination = directory.appendingPathComponent(Downloader.cacheFilename(url: url, key: "same-name", format: "flac", headers: [:]))
        do { _ = try await download(url); XCTFail("Failed move must throw") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("occupied").path)) }
    }
}
