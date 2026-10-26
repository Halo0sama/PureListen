import Foundation
import AudioToolbox

/// 文件探测与远端 seek 在后台完成，交给播放器后只负责解码，不在实时回调里访问网络。
public final class PreparedAudio: @unchecked Sendable {
    public let source: RemoteAudioFile
    let reader: RemoteAudioFile.Reader
    private final class Handles {
        var file: ExtAudioFileRef?
        var audioFile: AudioFileID?
        var context: AnyObject?
        func close() {
            if let file { ExtAudioFileDispose(file); self.file = nil }
            if let audioFile { AudioFileClose(audioFile); self.audioFile = nil }
            context = nil
        }
        deinit { close() }
    }
    private let handles = Handles()
    var file: ExtAudioFileRef? { handles.file }
    private let aac: DASHAACDecoder?
    private let context: ReadContext
    let fileFormat: AudioStreamBasicDescription
    let bits: Int
    let seconds: Double
    let startSeconds: Double

    private final class ReadContext {
        var length: Int64
        let read: (Int64, Int) throws -> Data
        var error: Error?
        init(length: Int64, read: @escaping (Int64, Int) throws -> Data) {
            self.length = length; self.read = read
        }
    }
    public static func prepare(source: RemoteAudioFile, format: String, codec: String = "",
                               position: Double = 0) async throws -> PreparedAudio {
        let reader = source.makeReader()
        let task = Task.detached(priority: .userInitiated) {
            try PreparedAudio(source: source, reader: reader, format: format, codec: codec, position: position)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: {
            reader.cancel(); task.cancel()
        })
    }
    private init(source: RemoteAudioFile, reader: RemoteAudioFile.Reader,
                 format: String, codec: String, position: Double) throws {
        self.source = source; self.reader = reader
        let length = try source.length(reader: reader)
        let head = try reader.read(0, 42)
        if codec.lowercased() == "mp4a.40.2" || (codec.isEmpty && format.lowercased() == "m4a"),
           let decoder = try? DASHAACDecoder(reader: reader, length: length, position: position) {
            aac = decoder
            context = ReadContext(length: length, read: reader.read)
            fileFormat = decoder.format; bits = 0; seconds = decoder.seconds; startSeconds = decoder.position
            return
        }
        aac = nil
        let context: ReadContext
        if codec.lowercased() == "flac", !head.starts(with: Data("fLaC".utf8)) {
            let flac = try RemoteFLACView(reader: reader, length: length)
            context = ReadContext(length: flac.length, read: flac.read)
        } else { context = ReadContext(length: length, read: reader.read) }
        self.context = context
        handles.context = context
        var audio: AudioFileID?
        let status = AudioFileOpenWithCallbacks(Unmanaged.passUnretained(context).toOpaque(), { raw, position, count, buffer, actual in
            let context = Unmanaged<ReadContext>.fromOpaque(raw).takeUnretainedValue()
            actual.pointee = 0
            do {
                let bytes = try context.read(position, Int(count))
                bytes.withUnsafeBytes { if let base = $0.baseAddress { memcpy(buffer, base, bytes.count) } }
                actual.pointee = UInt32(bytes.count)
                return noErr
            } catch { context.error = error; return kAudioFileUnspecifiedError }
        }, nil, { raw in Unmanaged<ReadContext>.fromOpaque(raw).takeUnretainedValue().length }, nil, 0, &audio)
        guard status == noErr, let audio else { throw context.error ?? Self.error("无法识别音频格式", status) }
        handles.audioFile = audio
        var wrapped: ExtAudioFileRef?
        let wrapStatus = ExtAudioFileWrapAudioFileID(audio, false, &wrapped)
        guard wrapStatus == noErr, let wrapped else {
            handles.close(); throw context.error ?? Self.error("无法创建流式解码器", wrapStatus)
        }
        handles.file = wrapped
        do {
            var description = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.size(ofValue: description))
            let result = ExtAudioFileGetProperty(wrapped, kExtAudioFileProperty_FileDataFormat, &size, &description)
            guard result == noErr, description.mSampleRate > 0 else { throw Self.error("无法读取音源格式", result) }
            fileFormat = description
            let flacHeader = try context.read(0, 42)
            bits = Int(description.mBitsPerChannel) > 0 ? Int(description.mBitsPerChannel)
                : (flacHeader.starts(with: Data("fLaC".utf8)) && flacHeader.count >= 22
                   ? (Int(flacHeader[20] & 1) << 4 | Int(flacHeader[21] >> 4)) + 1 : 0)
            var frames: Int64 = 0; size = UInt32(MemoryLayout.size(ofValue: frames))
            let durationStatus = ExtAudioFileGetProperty(wrapped, kExtAudioFileProperty_FileLengthFrames, &size, &frames)
            seconds = durationStatus == noErr ? Double(frames) / description.mSampleRate : 0
            startSeconds = min(max(position.isFinite ? position : 0, 0), max(seconds - 0.001, 0))
            if startSeconds > 0 {
                var pcm = AudioStreamBasicDescription(mSampleRate: description.mSampleRate,
                    mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
                    mBytesPerPacket: description.mChannelsPerFrame * 4, mFramesPerPacket: 1,
                    mBytesPerFrame: description.mChannelsPerFrame * 4,
                    mChannelsPerFrame: description.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
                let configured = ExtAudioFileSetProperty(wrapped, kExtAudioFileProperty_ClientDataFormat,
                    UInt32(MemoryLayout.size(ofValue: pcm)), &pcm)
                guard configured == noErr else { throw Self.error("无法配置解码器", configured) }
                let seek = ExtAudioFileSeek(wrapped, Int64(startSeconds * description.mSampleRate))
                guard seek == noErr else { throw context.error ?? Self.error("无法跳转到该位置", seek) }
            }
            try reader.check()
        } catch { handles.close(); throw error }
    }
    public func cancelReads() { reader.cancel() }
    var readError: Error? { aac?.error ?? context.error ?? source.snapshot.error }
    func configure(_ format: AudioStreamBasicDescription) -> OSStatus {
        if let aac { return aac.configure(format) }
        guard let file else { return kAudioFileUnspecifiedError }
        var format = format
        return ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                       UInt32(MemoryLayout.size(ofValue: format)), &format)
    }
    func read(_ frames: inout UInt32, _ buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        if let aac { return aac.read(&frames, buffers) }
        guard let file else { return kAudioFileUnspecifiedError }
        return ExtAudioFileRead(file, &frames, buffers)
    }
    deinit { handles.close() }
    private static func error(_ message: String, _ status: OSStatus) -> NSError {
        NSError(domain: "PureListen.Stream", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
