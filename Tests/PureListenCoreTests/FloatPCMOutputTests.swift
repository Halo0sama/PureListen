import XCTest
import AudioToolbox
@testable import PureListenCore

final class FloatPCMOutputTests: XCTestCase {
    private final class Buffers {
        let list: UnsafeMutableAudioBufferListPointer
        let storage: [UnsafeMutablePointer<Float32>]
        let lengths: [Int]
        let sentinel: Float32 = 12345
        init(channels: [Int], frames: Int) {
            list = AudioBufferList.allocate(maximumBuffers: channels.count)
            list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(channels.count)
            lengths = channels.map { $0 * frames }
            storage = lengths.map { count in
                let p = UnsafeMutablePointer<Float32>.allocate(capacity: count + 2)
                p.initialize(repeating: 12345, count: count + 2)
                return p
            }
            for i in channels.indices {
                list[i] = AudioBuffer(mNumberChannels: UInt32(channels[i]),
                                     mDataByteSize: UInt32(lengths[i] * MemoryLayout<Float32>.size),
                                     mData: storage[i].advanced(by: 1))
            }
        }
        func samples(_ index: Int = 0) -> [Float32] {
            Array(UnsafeBufferPointer(start: storage[index].advanced(by: 1), count: lengths[index]))
        }
        func assertGuards(file: StaticString = #filePath, line: UInt = #line) {
            for i in storage.indices {
                XCTAssertEqual(storage[i][0], sentinel, file: file, line: line)
                XCTAssertEqual(storage[i][lengths[i] + 1], sentinel, file: file, line: line)
            }
        }
        deinit {
            storage.forEach { $0.deallocate() }
            list.unsafeMutablePointer.deallocate()
        }
    }

    private func format(channels: Int = 2, planar: Bool = false) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
            mBytesPerPacket: UInt32((planar ? 1 : channels) * 4), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32((planar ? 1 : channels) * 4), mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32, mReserved: 0)
    }

    private func ring(_ samples: [Float32], channels: Int = 2) -> RingBuffer {
        let ring = RingBuffer(frames: 1024, channels: channels)
        samples.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, frames: samples.count / channels) }
        return ring
    }

    func testIntegerPhysicalFormatCannotBeUsedAsCallbackFormat() throws {
        var physical = format()
        physical.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        physical.mBitsPerChannel = 16
        physical.mBytesPerFrame = 4
        physical.mBytesPerPacket = 4
        XCTAssertThrowsError(try FloatPCMOutput(virtualFormat: physical))
        let callback = try FloatPCMOutput(virtualFormat: format())
        XCTAssertEqual(callback.decoderFormat.mBytesPerFrame, 8)
        let input: [Float32] = [-1, 32767.0 / 32768, 0.25, -0.5, 0, 0.75]
        let buffers = Buffers(channels: [2], frames: 3)
        var scratch = [Float32](repeating: 0, count: 6)
        let result = scratch.withUnsafeMutableBufferPointer {
            callback.render(ring: ring(input), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 1)
        }
        XCTAssertEqual(result.frames, 3)
        XCTAssertEqual(result.clamped, 0)
        XCTAssertEqual(buffers.samples(), input)
        buffers.assertGuards()
    }

    func testPlanarMultichannelBuffersUseCorrectAudioBufferListStride() throws {
        let output = try FloatPCMOutput(virtualFormat: format(channels: 4, planar: true))
        XCTAssertEqual(output.decoderFormat.mBytesPerFrame, 16)
        let input: [Float32] = [0.1, 0.2, 0.3, 0.4, -0.1, -0.2, -0.3, -0.4]
        let buffers = Buffers(channels: [1, 1, 1, 1], frames: 2)
        var scratch = [Float32](repeating: 0, count: 8)
        let result = scratch.withUnsafeMutableBufferPointer {
            output.render(ring: ring(input, channels: 4), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 1)
        }
        XCTAssertEqual(result.frames, 2)
        for channel in 0..<4 { XCTAssertEqual(buffers.samples(channel), [input[channel], input[4 + channel]]) }
        buffers.assertGuards()
    }

    func testMonoAndSoftwareAttenuation() throws {
        let output = try FloatPCMOutput(virtualFormat: format(channels: 1))
        let buffers = Buffers(channels: [1], frames: 4)
        var scratch = [Float32](repeating: 0, count: 4)
        _ = scratch.withUnsafeMutableBufferPointer {
            output.render(ring: ring([-1, -0.5, 0.5, 1], channels: 1), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 0.25)
        }
        XCTAssertEqual(buffers.samples(), [-0.25, -0.125, 0.125, 0.25])
        buffers.assertGuards()
    }

    func testZeroVolumeAlwaysProducesSilence() throws {
        let output = try FloatPCMOutput(virtualFormat: format())
        for gain in [Float32(0), Float32.nan] {
            let buffers = Buffers(channels: [2], frames: 2)
            var scratch = [Float32](repeating: 0, count: 4)
            _ = scratch.withUnsafeMutableBufferPointer {
                output.render(ring: ring([1, -1, 0.5, -0.5]), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: gain)
            }
            XCTAssertEqual(buffers.samples(), [0, 0, 0, 0])
            buffers.assertGuards()
        }
    }

    func testUnderrunPadsWithSilence() throws {
        let output = try FloatPCMOutput(virtualFormat: format())
        let buffers = Buffers(channels: [2], frames: 4)
        var scratch = [Float32](repeating: 0, count: 8)
        let result = scratch.withUnsafeMutableBufferPointer {
            output.render(ring: ring([0.5, -0.5]), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 1)
        }
        XCTAssertEqual(result.frames, 1)
        XCTAssertEqual(buffers.samples(), [0.5, -0.5, 0, 0, 0, 0, 0, 0])
        buffers.assertGuards()
    }

    func testUnexpectedBufferOrScratchSizeStaysSilentWithoutConsumingAudio() throws {
        for planar in [false, true] {
            let output = try FloatPCMOutput(virtualFormat: format(planar: planar))
            let buffers = Buffers(channels: [2], frames: 4)
            let ring = ring([0.5, -0.5, 0.2, -0.2])
            var scratch = [Float32](repeating: 0, count: 2)
            let result = scratch.withUnsafeMutableBufferPointer {
                output.render(ring: ring, output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 1)
            }
            XCTAssertEqual(result.frames, 0)
            XCTAssertTrue(buffers.samples().allSatisfy { $0 == 0 })
            XCTAssertEqual(ring.availableToRead, 2)
            buffers.assertGuards()
        }
    }

    func testInvalidSamplesAreClampedWithoutChangingValidSamples() throws {
        let output = try FloatPCMOutput(virtualFormat: format())
        let buffers = Buffers(channels: [2], frames: 3)
        var scratch = [Float32](repeating: 0, count: 6)
        let result = scratch.withUnsafeMutableBufferPointer {
            output.render(ring: ring([.nan, .infinity, 2, -2, 0.5, -0.5]), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 1)
        }
        XCTAssertEqual(result.clamped, 4)
        XCTAssertEqual(buffers.samples(), [0, 0, 1, -1, 0.5, -0.5])
        buffers.assertGuards()
    }

    func testRealPCM16FileDecodesIntoFloatCallbackWithoutBitReinterpretation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let input: [Int16] = [-32768, 32767, -16384, 16384, 0, 8192]
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); append(UInt32(36 + input.count * 2).littleEndian)
        data.append(Data("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(2).littleEndian)
        append(UInt32(48000).littleEndian); append(UInt32(48000 * 4).littleEndian)
        append(UInt16(4).littleEndian); append(UInt16(16).littleEndian)
        data.append(Data("data".utf8)); append(UInt32(input.count * 2).littleEndian)
        for value in input { append(value.littleEndian) }
        try data.write(to: url)
        var file: ExtAudioFileRef?
        XCTAssertEqual(ExtAudioFileOpenURL(url as CFURL, &file), noErr)
        let extFile = try XCTUnwrap(file)
        defer { ExtAudioFileDispose(extFile) }
        let output = try FloatPCMOutput(virtualFormat: format())
        var decoder = output.decoderFormat
        XCTAssertEqual(ExtAudioFileSetProperty(extFile, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &decoder), noErr)
        var samples = [Float32](repeating: 0, count: 6)
        var frames: UInt32 = 3
        let result = samples.withUnsafeMutableBytes { bytes -> OSStatus in
            var buffers = AudioBufferList(mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            return ExtAudioFileRead(extFile, &frames, &buffers)
        }
        XCTAssertEqual(result, noErr)
        XCTAssertEqual(frames, 3)
        XCTAssertEqual(samples, input.map { Float32($0) / 32768 })
        let buffers = Buffers(channels: [2], frames: 3)
        var scratch = [Float32](repeating: 0, count: 6)
        _ = scratch.withUnsafeMutableBufferPointer {
            output.render(ring: ring(samples), output: buffers.list.unsafeMutablePointer, scratch: $0, gain: 1)
        }
        XCTAssertEqual(buffers.samples(), samples)
        buffers.assertGuards()
    }
}
