import Foundation

/// B 站的 FLAC 位于单音轨 fragmented MP4 中；无转码取出原始 FLAC 帧，交给 CoreAudio 解码。
public enum FLACContainer {
    public static func prepare(_ url: URL) async throws -> URL {
        let task = Task.detached(priority: .userInitiated) { try unwrap(url); return url }
        return try await withTaskCancellationHandler(operation: { try await task.value },
                                                     onCancel: { task.cancel() })
    }

    private struct Box {
        var type: String
        var payload: Int
        var end: Int
    }

    private static func invalid() -> NSError {
        NSError(domain: "PureListen.FLAC", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Hi-Res 音轨封装不完整或不受支持，请重试或选择高音质"])
    }

    private static func number(_ bytes: Data, _ offset: Int, _ count: Int) throws -> UInt64 {
        guard offset >= 0, count > 0, offset <= bytes.count - count else { throw invalid() }
        return bytes[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func box(_ header: Data, at offset: Int, limit: Int) throws -> Box {
        let size32 = try number(header, 0, 4)
        let headerSize = size32 == 1 ? 16 : 8
        let size = size32 == 1 ? try number(header, 8, 8) : (size32 == 0 ? UInt64(limit - offset) : size32)
        guard size >= headerSize, size <= UInt64(limit - offset), header.count >= 8 else { throw invalid() }
        let type = String(bytes: header[4..<8], encoding: .ascii) ?? ""
        return Box(type: type, payload: offset + headerSize, end: offset + Int(size))
    }

    private static func children(_ data: Data, in range: Range<Int>) throws -> [Box] {
        var result: [Box] = []
        var offset = range.lowerBound
        while offset < range.upperBound {
            try Task.checkCancellation()
            let header = Data(data[offset..<min(offset + 16, range.upperBound)])
            let child = try box(header, at: offset, limit: range.upperBound)
            result.append(child)
            offset = child.end
        }
        return result
    }

    private static func child(_ type: String, of parent: Box, in data: Data, skip: Int = 0) throws -> Box {
        guard parent.payload + skip <= parent.end,
              let match = try children(data, in: (parent.payload + skip)..<parent.end).first(where: { $0.type == type })
        else { throw invalid() }
        return match
    }

    static func metadata(_ moov: Data) throws -> Data {
        let tracks = try children(moov, in: 0..<moov.count).filter { $0.type == "trak" }
        guard tracks.count == 1 else { throw invalid() }
        let media = try child("mdia", of: tracks[0], in: moov)
        let handler = try child("hdlr", of: media, in: moov)
        guard handler.end - handler.payload >= 12,
              String(bytes: moov[(handler.payload + 8)..<(handler.payload + 12)], encoding: .ascii) == "soun"
        else { throw invalid() }
        let minf = try child("minf", of: media, in: moov)
        let table = try child("stbl", of: minf, in: moov)
        let descriptions = try child("stsd", of: table, in: moov)
        guard try number(moov, descriptions.payload + 4, 4) == 1 else { throw invalid() }
        let sample = try child("fLaC", of: descriptions, in: moov, skip: 8)
        guard try number(moov, sample.payload + 8, 2) == 0 else { throw invalid() }
        let config = try child("dfLa", of: sample, in: moov, skip: 28)
        let start = config.payload + 4
        guard config.end - start >= 38, config.end - start <= 1_048_576 else { throw invalid() }
        var offset = start
        var first = true
        var last = false
        while offset < config.end {
            guard !last else { throw invalid() }
            let kind = try number(moov, offset, 1)
            let count = Int(try number(moov, offset + 1, 3))
            guard count <= config.end - offset - 4 else { throw invalid() }
            if first { guard kind & 0x7F == 0, count == 34 else { throw invalid() }; first = false }
            last = kind & 0x80 != 0
            offset += 4 + count
        }
        guard last else { throw invalid() }
        return Data("fLaC".utf8) + moov[start..<config.end]
    }

    static func unwrap(_ url: URL) throws {
        try Task.checkCancellation()
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let size = Int(try input.seekToEnd())
        try input.seek(toOffset: 0)
        if try input.read(upToCount: 4) == Data("fLaC".utf8) { return }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".flac-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        var offset = 0
        var hasMetadata = false
        var hasFragment = false
        var fragments = 0
        while offset < size {
            try Task.checkCancellation()
            try input.seek(toOffset: UInt64(offset))
            let atom = try box(input.read(upToCount: 16) ?? Data(), at: offset, limit: size)
            try input.seek(toOffset: UInt64(atom.payload))
            switch atom.type {
            case "moov":
                guard !hasMetadata, atom.end - atom.payload <= 16_777_216 else { throw invalid() }
                let data = try input.read(upToCount: atom.end - atom.payload) ?? Data()
                try output.write(contentsOf: metadata(data))
                hasMetadata = true
            case "moof":
                guard hasMetadata, !hasFragment, atom.end - atom.payload <= 16_777_216 else { throw invalid() }
                let data = try input.read(upToCount: atom.end - atom.payload) ?? Data()
                guard try children(data, in: 0..<data.count).filter({ $0.type == "traf" }).count == 1 else { throw invalid() }
                hasFragment = true
            case "mdat":
                guard hasMetadata, hasFragment else { throw invalid() }
                let sync = try input.read(upToCount: 2) ?? Data()
                guard sync.count == 2, sync[0] == 0xFF, sync[1] & 0xFE == 0xF8 else { throw invalid() }
                try input.seek(toOffset: UInt64(atom.payload))
                var remaining = atom.end - atom.payload
                while remaining > 0 {
                    try Task.checkCancellation()
                    let bytes = try input.read(upToCount: min(remaining, 1_048_576)) ?? Data()
                    guard !bytes.isEmpty else { throw invalid() }
                    try output.write(contentsOf: bytes)
                    remaining -= bytes.count
                }
                hasFragment = false
                fragments += 1
            default: break
            }
            offset = atom.end
        }
        guard hasMetadata, fragments > 0, !hasFragment else { throw invalid() }
        try output.synchronize()
        try output.close()
        try Task.checkCancellation()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
