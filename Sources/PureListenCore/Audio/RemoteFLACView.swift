import Foundation

/// 把有 sidx 的单音轨 FLAC DASH 映射为虚拟原生 FLAC，按需取片段，无需下载整首或转码。
final class RemoteFLACView {
    private struct Box { let type: String; let payload: Int64; let end: Int64 }
    private struct Segment {
        let physical: Int64
        let physicalSize: Int64
        let moofSize: Int64
        let virtual: Range<Int64>
    }
    let length: Int64
    private let header: Data
    private let reader: RemoteAudioFile.Reader
    private let segments: [Segment]
    private var validated: Set<Int> = []

    init(reader: RemoteAudioFile.Reader, length: Int64) throws {
        self.reader = reader
        var offset: Int64 = 0
        var metadata: Data?
        var index: (Data, Int64)?
        while offset < length, offset < 16_777_216 {
            let box = try Self.box(reader, at: offset, limit: length)
            if box.type == "moov" {
                guard box.end - box.payload <= 16_777_216 else { throw Self.invalid() }
                metadata = try FLACContainer.metadata(reader.read(box.payload, Int(box.end - box.payload)))
            }
            if box.type == "sidx" {
                guard box.end - box.payload <= 1_048_576 else { throw Self.invalid() }
                index = (try reader.read(box.payload, Int(box.end - box.payload)), box.end)
                break
            }
            offset = box.end
        }
        guard let metadata, let (sidx, indexEnd) = index else { throw Self.invalid() }
        header = metadata
        let version = try Self.n(sidx, 0, 1)
        guard version <= 1 else { throw Self.invalid() }
        guard let firstOffset = Int64(exactly: try Self.n(sidx, version == 0 ? 16 : 20, version == 0 ? 4 : 8)),
              firstOffset <= length - indexEnd else { throw Self.invalid() }
        let countOffset = version == 0 ? 22 : 30
        let count = Int(try Self.n(sidx, countOffset, 2))
        guard count > 0, count <= 10_000 else { throw Self.invalid() }
        let first = indexEnd + firstOffset
        let moof = try Self.box(reader, at: first, limit: length)
        guard moof.type == "moof", moof.end - moof.payload <= 1_048_576 else { throw Self.invalid() }
        let bytes = try reader.read(moof.payload, Int(moof.end - moof.payload))
        let trafs = try Self.children(bytes, 0..<bytes.count).filter { $0.type == "traf" }
        guard trafs.count == 1 else { throw Self.invalid() }
        let traf = trafs[0]
        let children = try Self.children(bytes, Int(traf.payload)..<Int(traf.end))
        guard let tfhd = children.first(where: { $0.type == "tfhd" }),
              let trun = children.first(where: { $0.type == "trun" }) else { throw Self.invalid() }
        let flags = try Self.n(bytes, Int(tfhd.payload), 4) & 0xFFFFFF
        var durationOffset = Int(tfhd.payload) + 8
        if flags & 1 != 0 { durationOffset += 8 }
        if flags & 2 != 0 { durationOffset += 4 }
        guard flags & 8 != 0, try Self.n(bytes, Int(trun.payload), 4) & 0xFFFFFF == 0x201 else { throw Self.invalid() }
        let duration = Int64(try Self.n(bytes, durationOffset, 4))
        let samples = Int64(try Self.n(bytes, Int(trun.payload) + 4, 4))
        guard duration > 0, samples > 0 else { throw Self.invalid() }
        let baseMoof = moof.end - first - samples * 4
        var physical = first
        var virtual = Int64(metadata.count)
        var segments: [Segment] = []
        for i in 0..<count {
            let start = countOffset + 2 + i * 12
            let reference = try Self.n(sidx, start, 4)
            guard reference & 0x80000000 == 0 else { throw Self.invalid() }
            let size = Int64(reference)
            let span = Int64(try Self.n(sidx, start + 4, 4))
            let packets = (span + duration - 1) / duration
            let moofSize = baseMoof + packets * 4
            let payload = size - moofSize - 8
            guard packets > 0, payload > 0, physical <= length - size,
                  virtual <= Int64.max - payload else { throw Self.invalid() }
            segments.append(.init(physical: physical, physicalSize: size, moofSize: moofSize,
                                  virtual: virtual..<(virtual + payload)))
            physical += size; virtual += payload
        }
        self.segments = segments; self.length = virtual
        try validate(0)
    }

    private func validate(_ index: Int) throws {
        guard !validated.contains(index) else { return }
        let segment = segments[index]
        let end = segment.physical + segment.physicalSize
        let moof = try Self.box(reader, at: segment.physical, limit: end)
        let mdat = try Self.box(reader, at: moof.end, limit: end)
        guard moof.type == "moof", moof.end - segment.physical == segment.moofSize,
              mdat.type == "mdat", mdat.payload == moof.end + 8, mdat.end == end else { throw Self.invalid() }
        validated.insert(index)
    }
    func read(_ offset: Int64, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0 else { throw Self.invalid() }
        guard offset < length else { return Data() }
        let end = offset + min(Int64(count), length - offset)
        var cursor = offset
        var result = Data()
        if cursor < header.count {
            let headerEnd = min(Int64(header.count), end)
            result.append(header[Int(cursor)..<Int(headerEnd)]); cursor = headerEnd
        }
        while cursor < end {
            var low = 0, high = segments.count
            while low < high {
                let mid = (low + high) / 2
                if segments[mid].virtual.upperBound <= cursor { low = mid + 1 } else { high = mid }
            }
            guard low < segments.count else { throw Self.invalid() }
            try validate(low)
            let segment = segments[low]
            let size = Int(min(end, segment.virtual.upperBound) - cursor)
            result.append(try reader.read(segment.physical + segment.moofSize + 8 + cursor - segment.virtual.lowerBound, size))
            cursor += Int64(size)
        }
        return result
    }
    private static func n(_ data: Data, _ offset: Int, _ count: Int) throws -> UInt64 {
        guard offset >= 0, count > 0, offset <= data.count - count else { throw invalid() }
        return data[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
    private static func box(_ reader: RemoteAudioFile.Reader, at offset: Int64, limit: Int64) throws -> Box {
        let bytes = try reader.read(offset, 16)
        let size32 = try n(bytes, 0, 4)
        let head: Int64 = size32 == 1 ? 16 : 8
        let size: Int64
        if size32 == 1 {
            guard let extended = Int64(exactly: try n(bytes, 8, 8)) else { throw invalid() }
            size = extended
        } else { size = size32 == 0 ? limit - offset : Int64(size32) }
        guard size >= head, offset <= limit - size else { throw invalid() }
        return Box(type: String(bytes: bytes[4..<8], encoding: .ascii) ?? "", payload: offset + head, end: offset + size)
    }
    private static func children(_ data: Data, _ range: Range<Int>) throws -> [Box] {
        var cursor = range.lowerBound
        var result: [Box] = []
        while cursor < range.upperBound {
            let size = Int(try n(data, cursor, 4))
            guard size >= 8, size <= range.upperBound - cursor else { throw invalid() }
            result.append(.init(type: String(bytes: data[(cursor + 4)..<(cursor + 8)], encoding: .ascii) ?? "",
                                payload: Int64(cursor + 8), end: Int64(cursor + size)))
            cursor += size
        }
        return result
    }
    private static func invalid() -> NSError {
        NSError(domain: "PureListen.StreamFLAC", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Hi-Res 片段索引不受支持，请选择高音质"])
    }
}
