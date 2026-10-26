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
}
