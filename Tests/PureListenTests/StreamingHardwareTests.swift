import XCTest
import PureListenCore
@testable import PureListen

@MainActor
final class StreamingHardwareTests: XCTestCase {
    func testRemotePlaybackSeekAndReconnectAtZeroOutputVolume() async throws {
        guard let path = ProcessInfo.processInfo.environment["PURELISTEN_STREAM_FIXTURE"],
              let value = ProcessInfo.processInfo.environment["PURELISTEN_HARDWARE_TEST_DEVICE"],
              let id = UInt32(value), let device = AudioDevice.deviceInfo(id) else {
            throw XCTSkip("Requires explicit remote fixture and output device; software volume remains zero")
        }
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PureListen.streaming.hardware.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "volumeMirror")
        defaults.set(false, forKey: "muteSystem")
        defaults.set(false, forKey: "blockOtherOutputs")
        defaults.set(0, forKey: "volume")
        let state = AppState(defaults: defaults, previewMode: true)
        var available = [device]
        state.outputDeviceSnapshot = { available }
        state.refreshDevices()
        state.player.ioDumpEnabled = true
        var creations = 0
        state.makeRemoteAudio = { url, format, headers in
            creations += 1
            return try RemoteAudioFile(url: url, format: format, headers: headers, directory: directory)
        }
        let originalRate = AudioDevice.nominalSampleRate(id)
        let originalMute = SystemOutput.isMuted(on: id)
        defer {
            state.shutdown(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let item = PlayableItem(title: "stream verification", artist: "test", source: .bilibili,
            downloadURL: raw["url"] as! String, format: raw["format"] as? String ?? "flac",
            headers: raw["headers"] as? [String: String] ?? [:], codec: raw["codec"] as? String ?? "")
        state.play(item: item)
        await state.playbackTask?.value
        XCTAssertEqual(state.playerState, .playing)
        XCTAssertGreaterThan(state.trackStatus.seconds, 0)
        XCTAssertLessThan(state.trackStatus.downloadFraction, 1)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(state.trackStatus.positionSeconds, 0)
        state.playPause()
        XCTAssertEqual(state.playerState, .paused)
        state.seek(to: 20)
        XCTAssertEqual(state.suspendedPlaybackPosition, 20)
        state.playPause()
        await state.playbackTask?.value
        XCTAssertEqual(state.playerState, .playing)
        for _ in 0..<60 {
            if state.trackStatus.positionSeconds > 20 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(state.trackStatus.positionSeconds, 20)
        let position = state.trackStatus.positionSeconds
        available = []; state.refreshDevices()
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertEqual(state.player.state, .idle)
        available = [try XCTUnwrap(AudioDevice.deviceInfo(id))]; state.refreshDevices()
        XCTAssertEqual(state.player.state, .idle)
        state.playPause(); await state.playbackTask?.value
        XCTAssertEqual(state.playerState, .playing)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(state.trackStatus.positionSeconds, position)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(state.volume, 0)
        state.playPause()
        XCTAssertFalse(state.player.ioDump.isEmpty)
        XCTAssertTrue(state.player.ioDump.allSatisfy { $0 == 0 })
        XCTAssertTrue(state.player.decodeDump.contains { $0 != 0 })
        state.shutdown()
        XCTAssertEqual(AudioDevice.nominalSampleRate(id), originalRate)
        XCTAssertEqual(SystemOutput.isMuted(on: id), originalMute)
        XCTAssertNotEqual(AudioDevice.hogOwner(id), getpid())
    }
}
