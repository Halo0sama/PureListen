import XCTest
import AudioToolbox
@testable import PureListenCore

final class DASHAACDecoderTests: XCTestCase {
    private func u32(_ number: UInt32) -> Data {
        var value = number.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private func atom(_ name: String, _ payload: Data) -> Data {
        u32(UInt32(payload.count + 8)) + Data(name.utf8) + payload
    }
    private func generatedDASH(in directory: URL) throws -> Data {
        let wavURL = directory.appendingPathComponent("source.wav")
        let encoded = directory.appendingPathComponent("encoded.m4a")
        var wav = Data()
        func text(_ string: String) { wav.append(contentsOf: string.utf8) }
        func little<T: FixedWidthInteger>(_ number: T) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
        }
        let frames = 44100 * 8
        text("RIFF"); little(UInt32(36 + frames * 4)); text("WAVEfmt "); little(UInt32(16))
        little(UInt16(1)); little(UInt16(2)); little(UInt32(44100)); little(UInt32(44100 * 4))
        little(UInt16(4)); little(UInt16(16)); text("data"); little(UInt32(frames * 4))
        for i in 0..<frames {
            let sample = Int16(sin(Double(i) * 0.04) * 2000)
            little(sample); little(sample)
        }
        try wav.write(to: wavURL)
        let encoder = Process()
        encoder.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        encoder.arguments = ["-f", "m4af", "-d", "aac", "-b", "128000", wavURL.path, encoded.path]
        try encoder.run(); encoder.waitUntilExit()
        XCTAssertEqual(encoder.terminationStatus, 0)
        let fileBytes = try Data(contentsOf: encoded)
        func number(_ offset: Int) -> Int { fileBytes[offset..<(offset + 4)].reduce(0) { $0 * 256 + Int($1) } }
        var offset = 0, moov = Data()
        while offset + 8 <= fileBytes.count {
            let size = number(offset)
            guard size >= 8, offset + size <= fileBytes.count else { throw URLError(.cannotDecodeContentData) }
            if String(bytes: fileBytes[(offset + 4)..<(offset + 8)], encoding: .ascii) == "moov" {
                moov = Data(fileBytes[offset..<(offset + size)])
            }
            offset += size
        }
        XCTAssertFalse(moov.isEmpty)
        var file: AudioFileID?
        XCTAssertEqual(AudioFileOpenURL(encoded as CFURL, .readPermission, 0, &file), noErr)
        let audio = try XCTUnwrap(file)
        defer { AudioFileClose(audio) }
        var packetCount: UInt64 = 0, propertySize = UInt32(8)
        XCTAssertEqual(AudioFileGetProperty(audio, kAudioFilePropertyAudioDataPacketCount, &propertySize, &packetCount), noErr)
        var packets: [Data] = []
        for i in 0..<packetCount {
            var data = Data(count: 65536)
            var bytes: UInt32 = 65536, count: UInt32 = 1
            var description = AudioStreamPacketDescription()
            let status = data.withUnsafeMutableBytes {
                AudioFileReadPacketData(audio, false, &bytes, &description, Int64(i), &count, $0.baseAddress!)
            }
            XCTAssertEqual(status, noErr)
            packets.append(Data(data.prefix(Int(bytes))))
        }
        let groups = [Array(packets.prefix(packets.count / 2)), Array(packets.dropFirst(packets.count / 2))]
        var fragments: [Data] = []
        for (i, group) in groups.enumerated() {
            let tfhd = atom("tfhd", u32(0x20038) + u32(1) + u32(1024) + u32(0) + u32(0))
            let sizes = group.reduce(Data()) { $0 + u32(UInt32($1.count)) }
            func fragment(_ dataOffset: UInt32) -> Data {
                let trun = atom("trun", u32(0x201) + u32(UInt32(group.count)) + u32(dataOffset) + sizes)
                return atom("moof", atom("mfhd", u32(0) + u32(UInt32(i + 1))) + atom("traf", tfhd + trun))
            }
            let first = fragment(0)
            fragments.append(fragment(UInt32(first.count + 8)) + atom("mdat", group.reduce(Data(), +)))
        }
        var sidx = u32(0) + u32(1) + u32(44100) + u32(0) + u32(0) + Data([0, 0, 0, 2])
        for i in 0..<2 { sidx.append(u32(UInt32(fragments[i].count)) + u32(UInt32(groups[i].count * 1024)) + u32(0x90000000)) }
        return atom("ftyp", Data("dash".utf8)) + moov + atom("sidx", sidx) + fragments.reduce(Data(), +)
    }

    func testGeneratedAACStartsWithoutScanningEntireDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = try generatedDASH(in: directory)
        let fixture = try HTTPFixture { _ in .init(body: body, chunkSize: 2048, chunkInterval: 0.04) }
        defer { fixture.stop() }
        let source = try RemoteAudioFile(url: fixture.baseURL + "/generated.m4a", format: "m4a", directory: directory)
        defer { source.cancel() }
        let prepared = try await PreparedAudio.prepare(source: source, format: "m4a", codec: "mp4a.40.2")
        let format = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
            mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        XCTAssertEqual(prepared.configure(format), noErr)
        var samples = [Float](repeating: 0, count: 8192 * 2)
        var count: UInt32 = 8192
        let status = samples.withUnsafeMutableBytes { bytes -> OSStatus in
            var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
                mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            return prepared.read(&count, &buffers)
        }
        XCTAssertEqual(status, noErr)
        XCTAssertGreaterThan(count, 0)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertTrue(samples.contains { $0 != 0 })
        XCTAssertFalse(source.snapshot.complete)
        XCTAssertLessThan(source.snapshot.received, source.snapshot.total)
    }
}
