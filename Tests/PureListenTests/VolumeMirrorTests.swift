import XCTest
import PureListenCore
@testable import PureListen

final class VolumeMirrorTests: XCTestCase {
    func testExclusiveOutputCanBeReadWhenDefaultOutputIsUnavailable() {
        let fallback = SystemOutput.Identity(id: 86, uid: "dac")
        XCTAssertEqual(VolumeMirror.snapshot(defaultDevice: nil, fallbackDevice: fallback,
                                             volume: { _ in 0.2 }),
                       .init(deviceID: 86, uid: "dac", volume: 0.2))
        let system = SystemOutput.Identity(id: 74, uid: "speakers")
        XCTAssertEqual(VolumeMirror.snapshot(defaultDevice: system, fallbackDevice: fallback,
                                             volume: { $0 == 74 ? Float.nan : Float(0.4) })?.volume, 0.4)
        XCTAssertEqual(VolumeMirror.snapshot(defaultDevice: system, fallbackDevice: fallback,
                                             volume: { $0 == 74 ? Float(0.6) : Float(1) })?.deviceID, 74)
    }
    func testRouteChangesAndDelayedFullVolumeOnlyResetBaseline() {
        var time = Date()
        var snapshot: VolumeMirror.Snapshot? = .init(deviceID: 1, uid: "speakers", volume: 0.2)
        let mirror = VolumeMirror(readSnapshot: { snapshot }, now: { time })
        var received: [Float] = []
        mirror.onSystemVolume = { received.append($0) }
        mirror.rebase()
        time.addTimeInterval(3)
        snapshot = .init(deviceID: 2, uid: "dac", volume: 1)
        mirror.tick()
        time.addTimeInterval(0.4)
        snapshot?.volume = 0.5 // 初始化期间的属性抖动也不是手动调节。
        mirror.tick()
        time.addTimeInterval(0.4)
        snapshot?.volume = 1
        mirror.tick()
        time.addTimeInterval(3)
        mirror.tick()
        XCTAssertTrue(received.isEmpty)
        snapshot?.volume = 0.3
        mirror.tick()
        XCTAssertEqual(received, [0.3])
    }

    func testUnavailableDeviceAndRecycledIDDoNotMirrorInitialVolume() {
        var time = Date()
        var snapshot: VolumeMirror.Snapshot? = .init(deviceID: 1, uid: "old", volume: 0.2)
        let mirror = VolumeMirror(readSnapshot: { snapshot }, now: { time })
        var received: [Float] = []
        mirror.onSystemVolume = { received.append($0) }
        mirror.rebase()
        time.addTimeInterval(3)
        snapshot = .init(deviceID: 1, uid: "recycled", volume: 1)
        mirror.tick()
        time.addTimeInterval(3)
        snapshot = nil
        mirror.tick()
        snapshot = .init(deviceID: 1, uid: "recycled", volume: 0.9)
        mirror.tick()
        time.addTimeInterval(3)
        mirror.tick()
        XCTAssertTrue(received.isEmpty)
        snapshot?.volume = 0.4
        mirror.tick()
        XCTAssertEqual(received, [0.4])
    }

    func testSelfInducedMuteAndRestoreAreNotUserVolumeChanges() {
        var time = Date()
        var volume: Float = 0.8
        let mirror = VolumeMirror(readSnapshot: { .init(deviceID: 1, uid: "speakers", volume: volume) }, now: { time })
        var received: [Float] = []
        mirror.onSystemVolume = { received.append($0) }
        mirror.rebase()
        time.addTimeInterval(3)
        volume = 0 // 应用静音后重新设基线。
        mirror.rebase()
        mirror.tick()
        time.addTimeInterval(3)
        volume = 0.8
        mirror.rebase()
        mirror.tick()
        time.addTimeInterval(3)
        mirror.tick()
        XCTAssertTrue(received.isEmpty)
        volume = 0.2
        mirror.tick()
        XCTAssertEqual(received, [0.2])
        volume = .nan
        mirror.tick()
        volume = 1
        mirror.tick()
        XCTAssertEqual(received, [0.2])
    }
}
