import Foundation
import AudioToolbox

/// AAC DASH 按片段读取包；避免系统 M4A 文件读取器在起播前扫描全部 moof。
final class DASHAACDecoder {
    private struct Box { let type: String; let payload: Int; let end: Int }
    private struct Segment { let offset: Int64; let size: Int64; let frames: Range<Int64> }
    let format: AudioStreamBasicDescription
    let seconds: Double
    let position: Double
    private let reader: RemoteAudioFile.Reader
    private let segments: [Segment]
    private let cookie: Data
    private var converter: AudioConverterRef?
    private var outputFormat = AudioStreamBasicDescription()
    private var segmentIndex = 0
    private var packetIndex = 0
    private var packetOffsets: [Int64] = []
    private var packetSizes: [Int] = []
    private var discard = 0
    private var scratch: UnsafeMutableRawPointer?
    private var scratchBytes = 0
    private final class PacketStorage {
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: 65536, alignment: 16)
        let description = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        deinit { bytes.deallocate(); description.deallocate() }
    }
    private let storage = PacketStorage()
    private var packet: UnsafeMutableRawPointer { storage.bytes }
    private var packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription> { storage.description }
    private(set) var error: Error?

    init(reader: RemoteAudioFile.Reader, length: Int64, position: Double) throws {
        self.reader = reader
        var cursor: Int64 = 0
        var moov: Data?
        var sidx: (Data, Int64)?
        while cursor < min(length, 16_777_216) {
            let head = try reader.read(cursor, 8)
            let size = Int64(try Self.n(head, 0, 4))
            guard size >= 8, size <= 16_777_216, cursor <= length - size else { throw Self.invalid() }
            let type = String(bytes: head[4..<8], encoding: .ascii)
            if type == "moov" { moov = try reader.read(cursor + 8, Int(size - 8)) }
            if type == "sidx" { sidx = (try reader.read(cursor + 8, Int(size - 8)), cursor + size); break }
            cursor += size
        }
        guard let moov, let (index, indexEnd) = sidx else { throw Self.invalid() }
        let tracks = try Self.boxes(moov, 0..<moov.count).filter { $0.type == "trak" }
        guard tracks.count == 1 else { throw Self.invalid() }
        let mdia = try Self.child("mdia", tracks[0], moov)
        let minf = try Self.child("minf", mdia, moov)
        let stbl = try Self.child("stbl", minf, moov)
        let stsd = try Self.child("stsd", stbl, moov)
        let entry = try Self.child("mp4a", stsd, moov, skip: 8)
        guard try Self.n(moov, entry.payload + 8, 2) == 0 else { throw Self.invalid() }
        let rate = Double(try Self.n(moov, entry.payload + 24, 4) >> 16)
        let channels = UInt32(try Self.n(moov, entry.payload + 16, 2))
        guard rate > 0, (1...8).contains(channels) else { throw Self.invalid() }
        let esds = try Self.child("esds", entry, moov, skip: 28)
        guard esds.end - esds.payload >= 4 else { throw Self.invalid() }
        cookie = Data(moov[(esds.payload + 4)..<esds.end])
        let config = try Self.audioConfig(cookie)
        guard config.count >= 2, config[0] >> 3 == 2 else { throw Self.invalid() }
        format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 2, mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: channels, mBitsPerChannel: 0, mReserved: 0)
        let version = try Self.n(index, 0, 1)
        guard version <= 1, Double(try Self.n(index, 8, 4)) == rate else { throw Self.invalid() }
        guard let firstOffset = Int64(exactly: try Self.n(index, version == 0 ? 16 : 20, version == 0 ? 4 : 8)),
              firstOffset <= length - indexEnd else { throw Self.invalid() }
        let countOffset = version == 0 ? 22 : 30
        let count = Int(try Self.n(index, countOffset, 2))
        guard count > 0, count <= 10_000 else { throw Self.invalid() }
        var physical = indexEnd + firstOffset
        var frames: Int64 = 0
        var segments: [Segment] = []
        for i in 0..<count {
            let entry = countOffset + 2 + 12 * i
            let size = Int64(try Self.n(index, entry, 4))
            let span = Int64(try Self.n(index, entry + 4, 4))
            guard size > 0, size < 0x80000000, span > 0, physical <= length - size else { throw Self.invalid() }
            segments.append(.init(offset: physical, size: size, frames: frames..<(frames + span)))
            physical += size; frames += span
        }
        self.segments = segments
        seconds = Double(frames) / rate
        self.position = min(max(position.isFinite ? position : 0, 0), max(seconds - 0.001, 0))
        let target = Int64(self.position * rate)
        segmentIndex = segments.firstIndex { $0.frames.contains(target) } ?? max(segments.count - 1, 0)
        try loadSegment()
        packetIndex = min(Int((target - segments[segmentIndex].frames.lowerBound) / 1024), packetSizes.count - 1)
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
        scratch?.deallocate()
    }

    func configure(_ output: AudioStreamBasicDescription) -> OSStatus {
        if let converter { AudioConverterDispose(converter); self.converter = nil }
        var input = format, output = output
        let status = AudioConverterNew(&input, &output, &converter)
        guard status == noErr, let converter else { return status }
        let cookieStatus = cookie.withUnsafeBytes {
            AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, UInt32(cookie.count), $0.baseAddress!)
        }
        guard cookieStatus == noErr else { return cookieStatus }
        outputFormat = output
        let packetStart = Double(segments[segmentIndex].frames.lowerBound + Int64(packetIndex * 1024)) / format.mSampleRate
        discard = max(0, Int((position - packetStart) * output.mSampleRate))
        return noErr
    }

    func read(_ frames: inout UInt32, _ buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        guard let converter else { return kAudioConverterErr_UnspecifiedError }
        let requested = frames
        let capacity = Int(requested) + discard
        let bytes = capacity * Int(outputFormat.mBytesPerFrame)
        if bytes > scratchBytes {
            scratch?.deallocate(); scratch = .allocate(byteCount: bytes, alignment: 16); scratchBytes = bytes
        }
        var output = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: outputFormat.mChannelsPerFrame,
            mDataByteSize: UInt32(bytes), mData: scratch))
        var received = UInt32(capacity)
        let status = AudioConverterFillComplexBuffer(converter, { _, count, data, description, raw in
            let decoder = Unmanaged<DASHAACDecoder>.fromOpaque(raw!).takeUnretainedValue()
            do {
                guard let bytes = try decoder.nextPacket() else { count.pointee = 0; return noErr }
                guard bytes.count <= 65536 else { throw DASHAACDecoder.invalid() }
                bytes.withUnsafeBytes { if let base = $0.baseAddress { memcpy(decoder.packet, base, bytes.count) } }
                decoder.packetDescription.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                                 mDataByteSize: UInt32(bytes.count))
                data.pointee.mNumberBuffers = 1
                data.pointee.mBuffers = AudioBuffer(mNumberChannels: decoder.format.mChannelsPerFrame,
                    mDataByteSize: UInt32(bytes.count), mData: decoder.packet)
                description?.pointee = decoder.packetDescription
                count.pointee = 1
                return noErr
            } catch { decoder.error = error; count.pointee = 0; return kAudioConverterErr_UnspecifiedError }
        }, Unmanaged.passUnretained(self).toOpaque(), &received, &output, nil)
        guard status == noErr else { frames = 0; return status }
        let skipped = min(Int(received), discard)
        let got = min(Int(requested), Int(received) - skipped)
        discard -= skipped
        if got > 0, let destination = buffers.pointee.mBuffers.mData, let scratch {
            memcpy(destination, scratch.advanced(by: skipped * Int(outputFormat.mBytesPerFrame)), got * Int(outputFormat.mBytesPerFrame))
        }
        frames = UInt32(got)
        buffers.pointee.mBuffers.mDataByteSize = UInt32(got) * outputFormat.mBytesPerFrame
        return noErr
    }

    private func nextPacket() throws -> Data? {
        if packetIndex >= packetSizes.count {
            segmentIndex += 1
            guard segmentIndex < segments.count else { return nil }
            try loadSegment(); packetIndex = 0
        }
        let index = packetIndex; packetIndex += 1
        return try reader.read(packetOffsets[index], packetSizes[index])
    }
    private func loadSegment() throws {
        let segment = segments[segmentIndex]
        let first = try reader.read(segment.offset, 8)
        let size = Int(try Self.n(first, 0, 4))
        guard first.count == 8, String(bytes: first[4..<8], encoding: .ascii) == "moof", size >= 8,
              size <= 1_048_576, Int64(size + 8) < segment.size else { throw Self.invalid() }
        let moof = try reader.read(segment.offset + 8, size - 8)
        let traf = try Self.boxes(moof, 0..<moof.count).filter { $0.type == "traf" }
        guard traf.count == 1 else { throw Self.invalid() }
        let trun = try Self.child("trun", traf[0], moof)
        guard try Self.n(moof, trun.payload, 4) & 0xFFFFFF == 0x201 else { throw Self.invalid() }
        let count = Int(try Self.n(moof, trun.payload + 4, 4))
        let dataOffset = Int64(try Self.n(moof, trun.payload + 8, 4))
        guard count > 0, count <= 100_000, dataOffset == size + 8 else { throw Self.invalid() }
        let mdat = try reader.read(segment.offset + Int64(size), 8)
        guard mdat.count == 8, String(bytes: mdat[4..<8], encoding: .ascii) == "mdat",
              Int64(try Self.n(mdat, 0, 4)) + Int64(size) == segment.size else { throw Self.invalid() }
        var cursor = segment.offset + dataOffset
        var offsets: [Int64] = [], sizes: [Int] = []
        for i in 0..<count {
            let bytes = Int(try Self.n(moof, trun.payload + 12 + i * 4, 4))
            guard bytes > 0, bytes <= 65536, cursor <= segment.offset + segment.size - Int64(bytes) else { throw Self.invalid() }
            offsets.append(cursor); sizes.append(bytes); cursor += Int64(bytes)
        }
        guard cursor == segment.offset + segment.size else { throw Self.invalid() }
        packetOffsets = offsets; packetSizes = sizes
    }
    private static func audioConfig(_ data: Data) throws -> Data {
        func descriptor(_ offset: Int) throws -> (UInt64, Range<Int>) {
            let tag = try n(data, offset, 1)
            var cursor = offset + 1, length = 0
            for _ in 0..<4 {
                let byte = Int(try n(data, cursor, 1)); cursor += 1
                length = length * 128 + (byte & 127)
                if byte & 128 == 0 {
                    guard length <= data.count - cursor else { throw invalid() }
                    return (tag, cursor..<(cursor + length))
                }
            }
            throw invalid()
        }
        let (tag, es) = try descriptor(0)
        guard tag == 3, es.count >= 3, data[es.lowerBound + 2] == 0 else { throw invalid() }
        let (decoderTag, decoder) = try descriptor(es.lowerBound + 3)
        guard decoderTag == 4, decoder.count >= 13, decoder.upperBound <= es.upperBound else { throw invalid() }
        let (configTag, config) = try descriptor(decoder.lowerBound + 13)
        guard configTag == 5, config.upperBound <= decoder.upperBound else { throw invalid() }
        return Data(data[config])
    }
    private static func n(_ data: Data, _ offset: Int, _ count: Int) throws -> UInt64 {
        guard offset >= 0, count > 0, offset <= data.count - count else { throw invalid() }
        return data[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
    private static func boxes(_ data: Data, _ range: Range<Int>) throws -> [Box] {
        var cursor = range.lowerBound, result: [Box] = []
        while cursor < range.upperBound {
            let size = Int(try n(data, cursor, 4))
            guard size >= 8, size <= range.upperBound - cursor else { throw invalid() }
            result.append(.init(type: String(bytes: data[(cursor + 4)..<(cursor + 8)], encoding: .ascii) ?? "",
                                payload: cursor + 8, end: cursor + size)); cursor += size
        }
        return result
    }
    private static func child(_ type: String, _ parent: Box, _ data: Data, skip: Int = 0) throws -> Box {
        guard parent.payload + skip <= parent.end,
              let result = try boxes(data, (parent.payload + skip)..<parent.end).first(where: { $0.type == type }) else { throw invalid() }
        return result
    }
    private static func invalid() -> NSError {
        NSError(domain: "PureListen.DASHAAC", code: 1, userInfo: [NSLocalizedDescriptionKey: "AAC 分段索引不受支持"])
    }
}
