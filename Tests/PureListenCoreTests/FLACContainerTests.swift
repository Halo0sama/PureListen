import XCTest
import AudioToolbox
@testable import PureListenCore

final class FLACContainerTests: XCTestCase {
    private func u32(_ value: UInt32) -> Data {
        var big = value.bigEndian
        return withUnsafeBytes(of: &big) { Data($0) }
    }
    private func atom(_ type: String, _ payload: Data) -> Data {
        u32(UInt32(payload.count + 8)) + Data(type.utf8) + payload
    }
    private var metadata: Data { Data([0x80, 0, 0, 34]) + Data(repeating: 0, count: 34) }
    private func container(tracks: Int = 1) -> Data {
        let config = atom("dfLa", Data(repeating: 0, count: 4) + metadata)
        let sample = atom("fLaC", Data(repeating: 0, count: 28) + config)
        let table = atom("stsd", u32(0) + u32(1) + sample)
        let handler = atom("hdlr", u32(0) + u32(0) + Data("soun".utf8))
        let track = atom("trak", atom("mdia", handler + atom("minf", atom("stbl", table))))
        let moov = atom("moov", (0..<tracks).reduce(Data()) { data, _ in data + track })
        return atom("ftyp", Data("dash".utf8)) + moov
            + atom("moof", atom("traf", Data())) + atom("mdat", Data([0xFF, 0xF8, 1, 2]))
            + atom("moof", atom("traf", Data())) + atom("mdat", Data([0xFF, 0xF9, 3, 4]))
    }
    private func temporary(_ bytes: Data, _ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audio.flac")
        try bytes.write(to: url)
        try run(url)
    }

    func testFragmentsAreUnwrappedWithoutChangingCompressedFramesAndCacheIsReusable() throws {
        try temporary(container()) { url in
            try FLACContainer.unwrap(url)
            let expected = Data("fLaC".utf8) + metadata + Data([0xFF, 0xF8, 1, 2, 0xFF, 0xF9, 3, 4])
            XCTAssertEqual(try Data(contentsOf: url), expected)
            try FLACContainer.unwrap(url)
            XCTAssertEqual(try Data(contentsOf: url), expected)
        }
    }

    func testTruncationAndMultipleTracksPreserveOriginalAndRemoveTemporaryFiles() throws {
        for invalid in [Data(container().dropLast()), container(tracks: 2), Data([0, 0, 0, 1])] {
            try temporary(invalid) { url in
                XCTAssertThrowsError(try FLACContainer.unwrap(url))
                XCTAssertEqual(try Data(contentsOf: url), invalid)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path), ["audio.flac"])
            }
        }
    }

    func testActualBilibiliFLACDecodesWithoutAudioOutput() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["PURELISTEN_FLAC_FIXTURE"] else {
            throw XCTSkip("Set PURELISTEN_FLAC_FIXTURE to a downloaded, complete fragmented FLAC container")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: url)
        _ = try await FLACContainer.prepare(url)
        var file: ExtAudioFileRef?
        XCTAssertEqual(ExtAudioFileOpenURL(url as CFURL, &file), noErr)
        let opened = try XCTUnwrap(file)
        defer { ExtAudioFileDispose(opened) }
        var source = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: source))
        XCTAssertEqual(ExtAudioFileGetProperty(opened, kExtAudioFileProperty_FileDataFormat, &size, &source), noErr)
        XCTAssertEqual(source.mFormatID, kAudioFormatFLAC)
        var pcm = AudioStreamBasicDescription(mSampleRate: source.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: source.mChannelsPerFrame * 4,
            mFramesPerPacket: 1, mBytesPerFrame: source.mChannelsPerFrame * 4,
            mChannelsPerFrame: source.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
        XCTAssertEqual(ExtAudioFileSetProperty(opened, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout.size(ofValue: pcm)), &pcm), noErr)
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 8192 * Int(source.mChannelsPerFrame))
        defer { samples.deallocate() }
        var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: source.mChannelsPerFrame,
            mDataByteSize: 8192 * source.mChannelsPerFrame * 4, mData: samples))
        var total = 0
        var nonzero = false
        for _ in 0..<16 {
            var frames: UInt32 = 8192
            XCTAssertEqual(ExtAudioFileRead(opened, &frames, &buffer), noErr)
            total += Int(frames)
            for index in 0..<(Int(frames) * Int(source.mChannelsPerFrame)) {
                XCTAssertTrue(samples[index].isFinite)
                nonzero = nonzero || samples[index] != 0
            }
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertTrue(nonzero)
        print("Hi-Res native decode: \(source.mSampleRate) Hz, \(source.mChannelsPerFrame) channels, \(total) PCM frames; no output device opened")
    }
}
