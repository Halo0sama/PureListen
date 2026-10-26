import XCTest
import AudioToolbox
@testable import PureListenCore

final class StreamingTests: XCTestCase {
    private func wav() -> Data {
        let frames = 44100 * 12
        var bytes = Data()
        func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + frames * 4)); text("WAVEfmt "); u32(16)
        u16(1); u16(2); u32(44100); u32(44100 * 4); u16(4); u16(16); text("data"); u32(UInt32(frames * 4))
        for index in 0..<frames { let sample = Int16(sin(Double(index) * 0.04) * 2000); u16(UInt16(bitPattern: sample)); u16(UInt16(bitPattern: sample)) }
        return bytes
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func readPCM(_ prepared: PreparedAudio, chunks: Int = 1) throws -> [Float] {
        let format = prepared.fileFormat
        let pcm = AudioStreamBasicDescription(mSampleRate: format.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: format.mChannelsPerFrame * 4,
            mFramesPerPacket: 1, mBytesPerFrame: format.mChannelsPerFrame * 4,
            mChannelsPerFrame: format.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
        XCTAssertEqual(prepared.configure(pcm), noErr)
        var values = [Float](repeating: 0, count: 8192 * Int(format.mChannelsPerFrame))
        var nonzero = false
        for _ in 0..<chunks {
            let result = values.withUnsafeMutableBytes { bytes -> OSStatus in
                var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: format.mChannelsPerFrame, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                var frames: UInt32 = 8192
                let status = prepared.read(&frames, &buffers)
                XCTAssertGreaterThan(frames, 0)
                return status
            }
            XCTAssertEqual(result, noErr)
            nonzero = nonzero || values.contains(where: { $0 != 0 })
        }
        XCTAssertTrue(values.allSatisfy(\.isFinite))
        XCTAssertTrue(nonzero)
        return values
    }

    func testDecodesBeforeWholeDownloadAndRangeSeekSkipsAhead() async throws {
        let body = wav()
        let receivedRange = expectation(description: "far seek requests a Range")
        receivedRange.assertForOverFulfill = false
        let fixture = try HTTPFixture(requestHandler: { _, headers in
            if let range = headers["range"], range.hasPrefix("bytes="),
               let start = Int(range.dropFirst(6).split(separator: "-")[0]),
               let end = Int(range.split(separator: "-").last ?? "") {
                receivedRange.fulfill()
                return .init(status: 206, headers: ["Content-Type": "audio/wav", "ETag": "test",
                    "Content-Range": "bytes \(start)-\(end)/\(body.count)"], body: body[start...end])
            }
            return .init(headers: ["Content-Type": "audio/wav", "ETag": "test"], body: body,
                         chunkSize: 65536, chunkInterval: 0.2)
        })
        defer { fixture.stop() }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try RemoteAudioFile(url: fixture.baseURL + "/music.wav", format: "wav", directory: dir)
        defer { source.cancel() }
        let start = Date()
        let first = try await PreparedAudio.prepare(source: source, format: "wav")
        defer { first.cancelReads() }
        _ = try readPCM(first)
        XCTAssertFalse(source.snapshot.complete)
        XCTAssertLessThan(source.snapshot.received, Int64(body.count))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.cacheURL.path))
        let seek = try await PreparedAudio.prepare(source: source, format: "wav", position: 10)
        defer { seek.cancelReads() }
        _ = try readPCM(seek)
        await fulfillment(of: [receivedRange], timeout: 2)
        XCTAssertFalse(source.snapshot.complete)
        XCTAssertEqual(seek.startSeconds, 10, accuracy: 0.001)
    }

    func testCancellationUnblocksReaderAndNeverPublishesPartialCache() async throws {
        let body = wav()
        let fixture = try HTTPFixture { _ in .init(body: body, chunkSize: 1024, chunkInterval: 0.2) }
        defer { fixture.stop() }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try RemoteAudioFile(url: fixture.baseURL + "/slow.wav", format: "wav", directory: dir)
        let reader = source.makeReader()
        let task = Task.detached { try reader.read(0, body.count) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = Date(); reader.cancel(); source.cancel()
        do { _ = try await task.value; XCTFail("cancelled read must fail") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.cacheURL.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains(where: { $0.hasSuffix(".part") }))
    }

    func testCancellingPreparationWakesMetadataReads() async throws {
        let body = wav()
        let fixture = try HTTPFixture { _ in .init(body: body, delay: 1) }
        defer { fixture.stop() }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = try RemoteAudioFile(url: fixture.baseURL + "/header.wav", format: "wav", directory: dir)
        defer { source.cancel() }
        let task = Task { try await PreparedAudio.prepare(source: source, format: "wav") }
        try await Task.sleep(nanoseconds: 30_000_000)
        let start = Date(); task.cancel()
        do { _ = try await task.value; XCTFail("cancelled prepare must fail") } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testCompletedDownloadIsCachedAndReusableOffline() async throws {
        let body = wav()
        let fixture = try HTTPFixture { _ in .init(body: body, chunkSize: 131072, chunkInterval: 0.005) }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = fixture.baseURL + "/cache.wav"
        let source = try RemoteAudioFile(url: url, format: "wav", directory: dir)
        defer { source.cancel() }
        for _ in 0..<200 {
            if source.snapshot.complete { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(source.snapshot.complete)
        XCTAssertEqual(try Data(contentsOf: source.cacheURL), body)
        fixture.stop()
        let cached = try RemoteAudioFile(url: url, format: "wav", directory: dir)
        defer { cached.cancel() }
        XCTAssertTrue(cached.snapshot.complete)
        let prepared = try await PreparedAudio.prepare(source: cached, format: "wav")
        _ = try readPCM(prepared)
    }

    func testBadHTTPAndTruncatedBodyDoNotBecomeCompleteAudio() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try HTTPFixture { path in
            path == "/html" ? .init(headers: ["Content-Type": "text/html"])
                : .init(body: Data(repeating: 1, count: 8192), declaredLength: 20000)
        }
        defer { fixture.stop() }
        for path in ["/html", "/truncated"] {
            let source = try RemoteAudioFile(url: fixture.baseURL + path, format: "wav", directory: dir)
            defer { source.cancel() }
            do { _ = try await PreparedAudio.prepare(source: source, format: "wav"); XCTFail("invalid stream must fail") } catch {}
            XCTAssertFalse(source.snapshot.complete)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.cacheURL.path))
        }
    }

    func testActualRemoteAudioStartsBeforeDownloadFinishes() async throws {
        guard let path = ProcessInfo.processInfo.environment["PURELISTEN_STREAM_FIXTURE"] else {
            throw XCTSkip("Set PURELISTEN_STREAM_FIXTURE to a private JSON with URL, format, codec, headers")
        }
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let format = raw["format"] as? String ?? "flac"
        let source = try RemoteAudioFile(url: raw["url"] as! String, format: format,
            headers: raw["headers"] as? [String: String] ?? [:], directory: dir)
        defer { source.cancel() }
        let start = Date()
        let prepared = try await PreparedAudio.prepare(source: source, format: format, codec: raw["codec"] as? String ?? "")
        defer { prepared.cancelReads() }
        _ = try readPCM(prepared, chunks: 16)
        let snapshot = source.snapshot
        XCTAssertFalse(snapshot.complete)
        XCTAssertLessThan(snapshot.received, snapshot.total)
        print("Streaming native decode: \(prepared.fileFormat.mSampleRate) Hz, \(prepared.bits) bit; first PCM in \(Date().timeIntervalSince(start)) s; downloaded \(snapshot.received)/\(snapshot.total) bytes; no audio device opened")
    }
}
