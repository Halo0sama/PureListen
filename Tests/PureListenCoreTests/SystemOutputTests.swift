import XCTest
import CoreAudio
@testable import PureListenCore

final class SystemOutputTests: XCTestCase {
    func testMuteRestoresOriginalDeviceEvenWhenDefaultChanges() {
        let identity = SystemOutput.Identity(id: 10, uid: "original")
        var writes: [(UInt32, UInt32, Float)] = []
        var session = SystemOutput.MuteSession(device: identity, controls: [
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 1, original: 0.2),
            .init(selector: kAudioDevicePropertyVolumeScalar, element: 2, original: 0.3)
        ])
        session.uidForDevice = { $0 == 10 ? "original" : "other" }
        session.writeControl = { id, _, element, value in writes.append((id, element, value)); return true }
        XCTAssertTrue(session.ensureMuted())
        XCTAssertEqual(writes.map(\.2), [0, 0])
        XCTAssertTrue(session.restore())
        XCTAssertEqual(writes.map(\.0), [10, 10, 10, 10])
        XCTAssertEqual(writes.suffix(2).map(\.2), [0.2, 0.3])
    }

    func testRemovedDeviceOrRecycledIDCannotReceiveStaleRestore() {
        let identity = SystemOutput.Identity(id: 10, uid: "old")
        for currentUID: String? in [nil, "replacement"] {
            var writes = 0
            var session = SystemOutput.MuteSession(device: identity, controls: [
                .init(selector: kAudioDevicePropertyMute, element: 0, original: 0)
            ])
            session.uidForDevice = { _ in currentUID }
            session.writeControl = { _, _, _, _ in writes += 1; return true }
            XCTAssertFalse(session.restore())
            XCTAssertFalse(session.ensureMuted())
            XCTAssertEqual(writes, 0)
        }
    }

    func testAlreadyMutedOutputRetainsOriginalMute() {
        var values: [Float] = []
        var session = SystemOutput.MuteSession(device: .init(id: 10, uid: "device"), controls: [
            .init(selector: kAudioDevicePropertyMute, element: 0, original: 1)
        ])
        session.uidForDevice = { _ in "device" }
        session.writeControl = { _, _, _, value in values.append(value); return true }
        XCTAssertTrue(session.ensureMuted())
        XCTAssertTrue(session.restore())
        XCTAssertEqual(values, [1, 1])
    }
    func testExclusivePlaybackUnmutesOnlyTargetAndRestoresMasterAndChannelMute() {
        let identity = SystemOutput.Identity(id: 10, uid: "dac")
        var writes: [(UInt32, UInt32, UInt32, Float)] = []
        var session = SystemOutput.MuteSession(device: identity, controls: [
            .init(selector: kAudioDevicePropertyMute, element: 0, original: 1),
            .init(selector: kAudioDevicePropertyMute, element: 1, original: 0),
            .init(selector: kAudioDevicePropertyMute, element: 2, original: 1)
        ], activeMuteValue: 0)
        session.uidForDevice = { _ in "dac" }
        session.writeControl = { id, selector, element, value in
            writes.append((id, selector, element, value)); return true
        }
        XCTAssertTrue(session.apply())
        XCTAssertEqual(writes.map(\.3), [0, 0, 0])
        XCTAssertTrue(session.restore())
        XCTAssertEqual(writes.suffix(3).map(\.3), [1, 0, 1])
        XCTAssertTrue(writes.allSatisfy { $0.0 == 10 && $0.1 == kAudioDevicePropertyMute })
        writes = []
        session.uidForDevice = { _ in "different-device" }
        XCTAssertFalse(session.apply())
        XCTAssertFalse(session.restore())
        XCTAssertTrue(writes.isEmpty)
    }

    func testControlWriteMustBeConfirmedByReadback() {
        var reads = 0
        var session = SystemOutput.MuteSession(device: .init(id: 10, uid: "dac"), controls: [
            .init(selector: kAudioDevicePropertyMute, element: 0, original: 1)
        ], activeMuteValue: 0)
        session.uidForDevice = { _ in "dac" }
        session.writeControl = { _, _, _, _ in true }
        session.readControl = { _, _, _ in reads += 1; return reads < 3 ? 1 : 0 }
        XCTAssertTrue(session.apply())
        XCTAssertGreaterThanOrEqual(reads, 4)
        session.readControl = { _, _, _ in 1 }
        XCTAssertFalse(session.apply()) // 只收到写入成功，而设备实际仍静音，不能视为可输出。
    }

}
