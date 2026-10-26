import XCTest
import PureListenCore
@testable import PureListen

@MainActor
final class PlaybackModesHardwareTests: XCTestCase {
    func testNaturalEndRepeatsLocallyAndCyclesQueueWithSilentHardwareOutput() async throws {
        guard let value = ProcessInfo.processInfo.environment["PURELISTEN_HARDWARE_TEST_DEVICE"],
              let id = UInt32(value), let device = AudioDevice.deviceInfo(id) else {
            throw XCTSkip("Requires an explicit output device; software output stays at zero")
        }
        let suite = "PureListen.modes.hardware.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "volumeMirror"); defaults.set(false, forKey: "muteSystem")
        defaults.set(false, forKey: "blockOtherOutputs"); defaults.set(0, forKey: "volume")
        let state = AppState(defaults: defaults, previewMode: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { state.shutdown(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: url) }
        var wav = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        let pcm = Data(repeating: 8, count: 48000 * 4 / 2)
        wav.append(contentsOf: "RIFF".utf8); append(UInt32(36 + pcm.count).littleEndian)
        wav.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(2).littleEndian)
        append(UInt32(48000).littleEndian); append(UInt32(48000 * 4).littleEndian)
        append(UInt16(4).littleEndian); append(UInt16(16).littleEndian)
        wav.append(contentsOf: "data".utf8); append(UInt32(pcm.count).littleEndian); wav.append(pcm)
        try wav.write(to: url)
        let originalRate = AudioDevice.nominalSampleRate(id), originalMute = SystemOutput.isMuted(on: id)
        state.outputDeviceSnapshot = { [device] }; state.refreshDevices()
        state.player.ioDumpEnabled = true
        var downloads = 0
        state.downloadAudio = { _, _, _ in downloads += 1; return url }
        let a = PlayableItem(id: "a", title: "A", artist: "test", source: .direct,
                             downloadURL: "https://example.invalid/a.wav", format: "wav")
        let b = PlayableItem(id: "b", title: "B", artist: "test", source: .direct,
                             downloadURL: "https://example.invalid/b.wav", format: "wav")
        state.itemQueue = [a, b]; state.playbackMode = .repeatOne
        state.play(item: a); await state.playbackTask?.value
        let firstID = state.player.playbackID
        for _ in 0..<120 {
            if state.player.playbackID != firstID && state.player.state == .playing { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotEqual(state.player.playbackID, firstID)
        XCTAssertEqual(state.currentItem?.id, "a")
        XCTAssertEqual(state.player.state, .playing)
        XCTAssertEqual(downloads, 1)
        state.playbackMode = .repeatAll
        for _ in 0..<120 {
            if state.currentItem?.id == "b", state.player.state == .playing { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state.currentItem?.id, "b")
        for _ in 0..<120 {
            if state.currentItem?.id == "a", state.player.state == .playing { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state.currentItem?.id, "a")
        try await Task.sleep(nanoseconds: 100_000_000)
        state.playPause()
        XCTAssertFalse(state.player.ioDump.isEmpty)
        XCTAssertTrue(state.player.ioDump.allSatisfy { $0 == 0 })
        XCTAssertEqual(state.volume, 0)
        state.shutdown()
        XCTAssertEqual(AudioDevice.nominalSampleRate(id), originalRate)
        XCTAssertEqual(SystemOutput.isMuted(on: id), originalMute)
        XCTAssertNotEqual(AudioDevice.hogOwner(id), getpid())
    }
}
