import XCTest
@testable import PureListen

final class MediaKeyTapTests: XCTestCase {
    func testSystemDefinedPackingAndRepeatBit() throws {
        let down = try XCTUnwrap(MediaKeyTap.KeyEvent(data1: (16 << 16) | 0x0A00, subtype: 8))
        XCTAssertEqual(down.code, 16)
        XCTAssertTrue(down.isDown)
        XCTAssertTrue(try XCTUnwrap(MediaKeyTap.KeyEvent(data1: (1 << 16) | 0x0A01, subtype: 8)).isDown)
        XCTAssertFalse(try XCTUnwrap(MediaKeyTap.KeyEvent(data1: (7 << 16) | 0x0B00, subtype: 8)).isDown)
        XCTAssertNil(MediaKeyTap.KeyEvent(data1: 0x0A00, subtype: 7))
        XCTAssertNil(MediaKeyTap.KeyEvent(data1: 0, subtype: 8))
    }

    func testVolumeDirectionsAndIndependentPlaybackSwitch() throws {
        let tap = MediaKeyTap()
        tap.shouldInterceptVolume = { true }
        tap.shouldInterceptPlayback = { false }
        var changes: [Float] = []
        var mutes = 0
        var plays = 0
        tap.onVolumeChange = { changes.append($0) }
        tap.onMuteToggle = { mutes += 1 }
        tap.onPlayPause = { plays += 1 }
        func event(_ code: Int, down: Bool = true) throws -> MediaKeyTap.KeyEvent {
            try XCTUnwrap(.init(data1: (code << 16) | (down ? 0x0A00 : 0x0B00), subtype: 8))
        }
        XCTAssertTrue(tap.handleKey(try event(0)))
        XCTAssertTrue(tap.handleKey(try event(1)))
        XCTAssertTrue(tap.handleKey(try event(0, down: false)))
        XCTAssertEqual(changes, [1 / 16, -1 / 16])
        XCTAssertTrue(tap.handleKey(try event(7)))
        XCTAssertTrue(tap.handleKey(try event(7, down: false)))
        XCTAssertEqual(mutes, 1)
        XCTAssertFalse(tap.handleKey(try event(16)))
        XCTAssertEqual(plays, 0)
        tap.shouldInterceptPlayback = { true }
        XCTAssertTrue(tap.handleKey(try event(16)))
        XCTAssertTrue(tap.handleKey(try event(16, down: false)))
        XCTAssertEqual(plays, 1)
        tap.shouldInterceptVolume = { false }
        XCTAssertFalse(tap.handleKey(try event(0)))
    }
}
