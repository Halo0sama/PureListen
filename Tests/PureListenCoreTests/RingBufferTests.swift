import XCTest
@testable import PureListenCore

final class RingBufferTests: XCTestCase {
    func testWraparoundAndResetDoNotExposeOldSamples() {
        let ring = RingBuffer(frames: 8, channels: 1)
        var input: [Float32] = [1, 2, 3, 4, 5, 6]
        input.withUnsafeBufferPointer { XCTAssertEqual(ring.write($0.baseAddress!, frames: 6), 6) }
        var output = [Float32](repeating: 0, count: 5)
        output.withUnsafeMutableBufferPointer { XCTAssertEqual(ring.read(into: $0.baseAddress!, frames: 5), 5) }
        input = [7, 8, 9, 10, 11, 12]
        input.withUnsafeBufferPointer { XCTAssertEqual(ring.write($0.baseAddress!, frames: 6), 6) }
        output = [Float32](repeating: 0, count: 8)
        output.withUnsafeMutableBufferPointer { XCTAssertEqual(ring.read(into: $0.baseAddress!, frames: 8), 7) }
        XCTAssertEqual(output, [6, 7, 8, 9, 10, 11, 12, 0])
        ring.reset()
        output.withUnsafeMutableBufferPointer { XCTAssertEqual(ring.read(into: $0.baseAddress!, frames: 8), 0) }
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
    }

    func testConcurrentProducerAndConsumerPreserveFrameOrder() {
        let ring = RingBuffer(frames: 1024, channels: 2)
        let total = 100000
        let group = DispatchGroup()
        var received: [Float32] = []
        let deadline = Date().addingTimeInterval(5)
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            var written = 0
            while written < total && Date() < deadline {
                let frames = min(127, total - written)
                let input = (written..<(written + frames)).flatMap { [Float32($0), -Float32($0)] }
                let count = input.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: frames) }
                written += count
                if count == 0 { Thread.sleep(forTimeInterval: 0.0001) }
            }
        }
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            var buffer = [Float32](repeating: 0, count: 83 * 2)
            while received.count / 2 < total && Date() < deadline {
                let count = buffer.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frames: 83) }
                received.append(contentsOf: buffer.prefix(count * 2))
                if count == 0 { Thread.sleep(forTimeInterval: 0.0001) }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 6), .success)
        XCTAssertEqual(received.count, total * 2)
        for frame in 0..<(received.count / 2) {
            XCTAssertEqual(received[frame * 2], Float32(frame))
            XCTAssertEqual(received[frame * 2 + 1], -Float32(frame))
        }
    }
}
