import XCTest
import PureListenCore
@testable import PureListen

@MainActor
final class AppStateTests: XCTestCase {
    private func makeState(_ values: [String: Any] = [:]) -> (AppState, UserDefaults, String) {
        let suite = "PureListen.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        return (AppState(defaults: defaults, previewMode: true), defaults, suite)
    }

    private func item(_ name: String) -> PlayableItem {
        PlayableItem(id: name, title: name, artist: "test", source: .bilibili,
                     downloadURL: "https://example.com/\(name).m4a", format: "m4a")
    }

    func testPreferencesPreserveMuteAndDisabledMirror() {
        let (state, defaults, suite) = makeState(["volume": 0.0, "volumeMirror": false, "autoResume": false])
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(state.volume, 0)
        XCTAssertEqual(state.player.volume, 0)
        XCTAssertFalse(state.systemVolumeMirror)
        XCTAssertFalse(state.autoResume)
        state.level = .hires
        state.networkMode = .direct
        XCTAssertEqual(defaults.string(forKey: "level"), "hires")
        XCTAssertEqual(defaults.string(forKey: "networkMode"), "direct")
        XCTAssertTrue(state.devices.isEmpty)
    }

    func testLatestPlaybackWinsEvenWhenOldRequestIgnoresCancellation() async throws {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let starts = (0..<3).map { expectation(description: "download \($0) started") }
        var pending: [CheckedContinuation<URL, Error>] = []
        state.downloadAudio = { _, _, _ in
            try await withCheckedThrowingContinuation { continuation in
                pending.append(continuation)
                starts[pending.count - 1].fulfill()
            }
        }
        state.play(item: item("A"))
        let first = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [starts[0]], timeout: 2)
        state.play(item: item("B"))
        let second = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [starts[1]], timeout: 2)
        state.play(item: item("A")) // 回到同一条目，索引或歌曲 id 相等也不能接受旧请求。
        let latest = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [starts[2]], timeout: 2)
        pending[2].resume(returning: URL(fileURLWithPath: "/nonexistent/test.m4a"))
        await latest.value
        let latestState = state.playerState
        pending[0].resume(throwing: NSError(domain: "stale", code: 1, userInfo: [NSLocalizedDescriptionKey: "old error"]))
        pending[1].resume(returning: URL(fileURLWithPath: "/nonexistent/stale.m4a"))
        await first.value
        await second.value
        XCTAssertEqual(state.currentItem?.id, "A")
        XCTAssertEqual(state.player.trackStatus.title, "A")
        XCTAssertEqual(state.playerState, latestState)
        XCTAssertNil(state.playbackTask)
    }

    func testNextAndPreviousStayInMultipartQueue() {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.downloadAudio = { _, _, _ in throw CancellationError() }
        let parts = [item("P1"), item("P2"), item("P3")]
        state.itemQueue = parts
        state.play(item: parts[0])
        state.playNext()
        XCTAssertEqual(state.currentItem?.id, "P2")
        state.playPrevious()
        XCTAssertEqual(state.currentItem?.id, "P1")
        state.playPrevious()
        XCTAssertEqual(state.currentItem?.id, "P1")
        state.play(item: parts[2])
        state.playNext()
        XCTAssertEqual(state.player.state, .idle)
        XCTAssertNil(state.playbackTask)
    }

    func testPauseDuringDownloadCancelsAndPreventsLatePlayback() async throws {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let started = expectation(description: "download started")
        var pending: CheckedContinuation<URL, Error>?
        state.downloadAudio = { _, _, _ in
            try await withCheckedThrowingContinuation { continuation in pending = continuation; started.fulfill() }
        }
        state.play(item: item("waiting"))
        let task = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [started], timeout: 2)
        state.playPause()
        pending?.resume(returning: URL(fileURLWithPath: "/nonexistent/test.m4a"))
        await task.value
        XCTAssertEqual(state.playerState, .idle)
        XCTAssertEqual(state.player.trackStatus.title, "")
        XCTAssertNil(state.playbackTask)
    }

    func testChangingDeviceRetainsBilibiliItemAndQueue() {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.downloadAudio = { _, _, _ in throw CancellationError() }
        let parts = [item("P1"), item("P2")]
        state.itemQueue = parts
        state.play(item: parts[1])
        let device = AudioDeviceInfo(id: 0, uid: "test-only", name: "Test", isBuiltIn: false,
                                     currentRate: 48000, hasOutput: true)
        state.selectDevice(device)
        XCTAssertEqual(state.currentItem?.id, "P2")
        XCTAssertEqual(state.itemQueue.map(\.id), ["P1", "P2"])
        XCTAssertNotNil(state.playbackTask)
    }
}
