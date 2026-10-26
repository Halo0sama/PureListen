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
        XCTAssertEqual(state.networkMode, .direct)
        state.level = .hires
        state.networkMode = .system
        XCTAssertEqual(defaults.string(forKey: "level"), "hires")
        XCTAssertEqual(defaults.string(forKey: "networkMode"), "system")
        let restored = AppState(defaults: defaults, previewMode: true)
        XCTAssertEqual(restored.networkMode, .system)
        restored.shutdown()
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
        XCTAssertNil(state.playbackTask)
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertEqual(state.volume, 0.1)
    }
    private var speakers: AudioDeviceInfo {
        AudioDeviceInfo(id: 101, uid: "speakers", name: "扬声器", isBuiltIn: true,
                        currentRate: 48000, hasOutput: true)
    }
    private func dac(_ id: UInt32 = 201, uid: String = "dac") -> AudioDeviceInfo {
        AudioDeviceInfo(id: id, uid: uid, name: "USB DAC", isBuiltIn: false,
                        currentRate: 48000, hasOutput: true)
    }

    func testSafeDefaultVolumeAlsoAppliesToEngine() {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(state.volume, 0.1)
        XCTAssertEqual(state.player.volume, 0.1)
        XCTAssertEqual(ExclusivePlayer().volume, 0.1)
    }

    func testPinnedDACRemainsSelectedAcrossDisconnectAndNewDeviceID() async {
        let (state, defaults, suite) = makeState(["devicePinned": true, "deviceUID": "dac"])
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.reconcileDevices([speakers, dac()])
        state.currentItem = item("P1")
        state.itemQueue = [item("P1"), item("P2")]
        state.playerState = .playing
        state.trackStatus.positionSeconds = 37.5
        state.volume = 1
        state.reconcileDevices([speakers])
        XCTAssertNil(state.selectedDevice) // 不回退到扬声器。
        XCTAssertEqual(state.player.deviceID, 0)
        XCTAssertFalse(state.autoDevice)
        XCTAssertEqual(defaults.string(forKey: "deviceUID"), "dac")
        XCTAssertEqual(state.suspendedPlaybackPosition, 37.5)
        state.reconcileDevices([speakers, dac(303)])
        for _ in 0..<20 { state.reconcileDevices([speakers, dac(303)]) }
        await Task.yield() // 已排队的旧 idle/进度回调也不能覆盖保留状态。
        XCTAssertEqual(state.selectedDevice?.id, 303)
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertEqual(state.trackStatus.positionSeconds, 37.5)
        XCTAssertEqual(state.suspendedPlaybackPosition, 37.5)
        XCTAssertEqual(state.currentItem?.id, "P1")
        XCTAssertEqual(state.itemQueue.map(\.id), ["P1", "P2"])
        XCTAssertNil(state.playbackTask)
        XCTAssertEqual(state.player.state, .idle)
        XCTAssertEqual(state.volume, 0.1)
        XCTAssertEqual(state.player.volume, 0.1)
    }

    func testDeviceChangesNeverStartPlayingFromAnyState() {
        for initial in [ExclusivePlayer.State.playing, .paused, .loading("waiting"), .idle, .error("lost")] {
            let (state, defaults, suite) = makeState()
            state.reconcileDevices([speakers])
            state.currentItem = item("A")
            state.playerState = initial
            state.trackStatus.positionSeconds = 12
            state.reconcileDevices([speakers, dac()])
            XCTAssertEqual(state.selectedDevice?.uid, "dac")
            XCTAssertEqual(state.playerState, .paused)
            XCTAssertNil(state.playbackTask)
            XCTAssertEqual(state.suspendedPlaybackPosition, 12)
            state.reconcileDevices([speakers])
            XCTAssertEqual(state.selectedDevice?.uid, "speakers")
            XCTAssertEqual(state.playerState, .paused)
            XCTAssertNil(state.playbackTask)
            state.shutdown(); defaults.removePersistentDomain(forName: suite)
        }
    }

    func testDisconnectDuringDownloadRejectsLateCompletionAfterReinsert() async throws {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.reconcileDevices([dac()])
        let started = expectation(description: "download started")
        var pending: CheckedContinuation<URL, Error>?
        state.downloadAudio = { _, _, _ in
            try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        state.play(item: item("A"))
        let task = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [started], timeout: 2)
        state.reconcileDevices([])
        let stoppedID = state.player.playbackID
        state.reconcileDevices([dac(303)])
        let reinsertedID = state.player.playbackID
        XCTAssertNotEqual(stoppedID, reinsertedID)
        pending?.resume(returning: URL(fileURLWithPath: "/nonexistent/late.m4a"))
        await task.value
        await Task.yield()
        XCTAssertEqual(state.player.playbackID, reinsertedID) // playFile 没有被晚到的完成回调调用。
        XCTAssertEqual(state.player.trackStatus.title, "")
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertNil(state.playbackTask)
    }

    func testOnlyExplicitPlayContinuesAfterReinsertAndPreservesSeek() async throws {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.reconcileDevices([dac()])
        state.currentItem = item("A")
        state.trackStatus.seconds = 120
        state.trackStatus.positionSeconds = 25
        state.playerState = .paused
        state.reconcileDevices([])
        state.reconcileDevices([dac(303)])
        state.seek(to: 42)
        XCTAssertEqual(state.suspendedPlaybackPosition, 42)
        let started = expectation(description: "explicit playback starts download")
        state.downloadAudio = { _, _, _ in started.fulfill(); throw CancellationError() }
        XCTAssertNil(state.playbackTask)
        state.playPause()
        let task = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [started], timeout: 2)
        await task.value
        XCTAssertNil(state.suspendedPlaybackPosition)
        XCTAssertEqual(state.currentItem?.id, "A")
    }

    func testUnchangedDeviceAndHogDefaultChangesDoNotInterrupt() {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.reconcileDevices([speakers, dac()], defaultID: 201)
        state.playerState = .playing
        state.volume = 0.7
        var updated = dac()
        updated.currentRate = 96000
        state.reconcileDevices([updated, speakers], defaultID: speakers.id)
        XCTAssertEqual(state.playerState, .playing)
        XCTAssertEqual(state.volume, 0.7)
        XCTAssertEqual(state.selectedDevice?.currentRate, 96000)
        XCTAssertNil(state.suspendedPlaybackPosition)
    }

    func testReusedIDOrNewIDForSameUIDRequiresExplicitPlay() {
        for replacement in [dac(201, uid: "different"), dac(303)] {
            let (state, defaults, suite) = makeState()
            state.reconcileDevices([dac()])
            state.currentItem = item("A")
            state.playerState = .playing
            state.volume = 0
            state.reconcileDevices([replacement])
            XCTAssertEqual(state.selectedDevice?.uid, replacement.uid)
            XCTAssertEqual(state.playerState, .paused)
            XCTAssertEqual(state.volume, 0) // 不把静音提升到 10%。
            XCTAssertNil(state.playbackTask)
            state.shutdown(); defaults.removePersistentDomain(forName: suite)
        }
    }

    func testFastReplugInvalidatesEvenWhenIDAndUIDAreReused() async {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.reconcileDevices([dac()])
        state.currentItem = item("A")
        state.playerState = .playing
        state.trackStatus.positionSeconds = 13
        state.volume = 1
        state.scheduleHotplugHandling(invalidatedDeviceID: 201)
        state.reconcileDevices([dac()])
        state.volumeMirror.onSystemVolume?(1)
        await Task.yield()
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertEqual(state.suspendedPlaybackPosition, 13)
        XCTAssertEqual(state.volume, 0.1)
        XCTAssertNil(state.playbackTask)
        XCTAssertEqual(state.player.state, .idle)
    }

    func testMultipleDACsDoNotFollowDefaultAwayFromHoggedDevice() {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let second = dac(202, uid: "second")
        state.reconcileDevices([speakers, dac(), second], defaultID: 201)
        state.playerState = .playing
        state.volume = 0.4
        state.reconcileDevices([second, speakers, dac()], defaultID: 202)
        XCTAssertEqual(state.selectedDevice?.uid, "dac")
        XCTAssertEqual(state.playerState, .playing)
        XCTAssertEqual(state.volume, 0.4)
    }

    func testNeteaseIndexAndProgressSurviveDeviceChange() {
        let (state, defaults, suite) = makeState()
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite) }
        state.reconcileDevices([dac()])
        state.tracks = [NCTrack(id: 1, name: "track", artists: "artist", album: "album", durationMs: 120000, vipOnly: false)]
        state.currentIndex = 0
        state.trackStatus.positionSeconds = 9
        state.playerState = .paused
        state.reconcileDevices([speakers])
        XCTAssertNil(state.currentItem)
        XCTAssertEqual(state.currentIndex, 0)
        XCTAssertEqual(state.tracks.map(\.id), [1])
        XCTAssertEqual(state.suspendedPlaybackPosition, 9)
        XCTAssertNil(state.playbackTask)
    }

}
