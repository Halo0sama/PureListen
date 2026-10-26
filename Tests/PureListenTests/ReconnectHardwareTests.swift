import XCTest
import PureListenCore
@testable import PureListen

@MainActor
final class ReconnectHardwareTests: XCTestCase {
    /// 显式启用：注入设备断开/重连快照，按钮动作驱动真实 IO；不声称执行了物理拔插。
    func testExplicitPlayRebuildsRealOutputAfterSimulatedReconnect() async throws {
        guard let value = ProcessInfo.processInfo.environment["PURELISTEN_HARDWARE_TEST_DEVICE"],
              let id = UInt32(value), let device = AudioDevice.deviceInfo(id) else {
            throw XCTSkip("需显式指定硬件验证设备")
        }
        let suite = "PureListen.hardware.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "volumeMirror")
        defaults.set(true, forKey: "blockOtherOutputs")
        let state = AppState(defaults: defaults, previewMode: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer {
            state.shutdown()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: url)
        }
        // 五秒非零 PCM16，但引擎输出音量始终为 0。
        let pcm = Data(repeating: 8, count: 48000 * 2 * 2 * 5)
        var wav = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: "RIFF".utf8); append(UInt32(36 + pcm.count).littleEndian)
        wav.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(2).littleEndian)
        append(UInt32(48000).littleEndian); append(UInt32(48000 * 4).littleEndian)
        append(UInt16(4).littleEndian); append(UInt16(16).littleEndian)
        wav.append(contentsOf: "data".utf8); append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)
        try wav.write(to: url)

        let originalRate = AudioDevice.nominalSampleRate(id)
        let originalMute = SystemOutput.isMuted(on: id)
        var available = [device]
        state.outputDeviceSnapshot = { available }
        state.refreshDevices()
        state.volume = 0
        state.player.ioDumpEnabled = true
        var downloads = 0
        state.downloadAudio = { _, _, _ in downloads += 1; return url }
        let item = PlayableItem(id: "generated", title: "reconnect verification", artist: "test", source: .direct,
                                downloadURL: "https://example.invalid/generated.wav", format: "wav")
        state.play(item: item)
        await state.playbackTask?.value
        XCTAssertEqual(state.player.state, .playing)
        state.seek(to: 1)
        try await Task.sleep(nanoseconds: 180_000_000)
        let position = state.trackStatus.positionSeconds
        XCTAssertGreaterThan(position, 1)

        available = []
        state.refreshDevices()
        XCTAssertEqual(state.player.state, .idle)
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertEqual(state.suspendedPlaybackPosition, position)
        // 重现恢复动作不能依赖当前浏览列表或 currentItem 的情况。
        state.currentItem = nil
        state.currentIndex = -1
        state.tracks = []
        available = [try XCTUnwrap(AudioDevice.deviceInfo(id))]
        state.refreshDevices()
        XCTAssertEqual(state.player.state, .idle)
        XCTAssertNil(state.playbackTask)
        state.playPause()
        XCTAssertEqual(state.player.state, .playing)
        XCTAssertEqual(state.playerState, .playing)
        XCTAssertEqual(state.player.trackStatus.title, item.title)
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertGreaterThan(state.trackStatus.positionSeconds, position)
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(state.volume, 0)
        state.playPause()
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertFalse(state.player.ioDump.isEmpty)
        XCTAssertTrue(state.player.ioDump.allSatisfy { $0 == 0 })
        state.shutdown()
        XCTAssertEqual(AudioDevice.nominalSampleRate(id), originalRate)
        XCTAssertEqual(SystemOutput.isMuted(on: id), originalMute)
        XCTAssertNotEqual(AudioDevice.hogOwner(id), getpid())
    }
}
