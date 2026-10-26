import Foundation
import Synchronization
import Darwin

/// 下载写磁盘；读取只在解码线程等待。未完成的文件不会作为完整缓存发布。
public final class RemoteAudioFile: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public struct Snapshot {
        public let received: Int64
        public let total: Int64
        public let contiguous: Int64
        public let complete: Bool
        public let error: Error?
    }
    public final class Reader: @unchecked Sendable {
        private let cancelled = Atomic<Bool>(false)
        let source: RemoteAudioFile
        init(_ source: RemoteAudioFile) { self.source = source }
        public func cancel() { cancelled.store(true, ordering: .releasing); source.wake() }
        func check() throws {
            if cancelled.load(ordering: .acquiring) { throw CancellationError() }
        }
        func read(_ offset: Int64, _ count: Int) throws -> Data {
            try source.read(offset, count, reader: self)
        }
    }
    private struct Transfer {
        var offset: Int64
        var range: Range<Int64>?
        var accepted = false
    }
    public let cacheURL: URL
    private let partialURL: URL
    private let descriptor: Int32
    private let condition = NSCondition()
    private var session: URLSession?
    private var request: URLRequest?
    private var transfers: [Int: Transfer] = [:]
    private var intervals: [Range<Int64>] = []
    private var total: Int64 = 0
    private var sequentialBytes: Int64 = 0
    private var done = false
    private var failure: Error?
    private var cancelled = false
    private var entityTag: String?
    private var rangesSupported = true
    private var lastActivity = Date()

    public var snapshot: Snapshot {
        condition.lock(); defer { condition.unlock() }
        return Snapshot(received: intervals.reduce(0) { $0 + $1.count64 }, total: total,
                        contiguous: intervals.first?.lowerBound == 0 ? intervals.first!.upperBound : 0,
                        complete: done, error: failure)
    }
    public func makeReader() -> Reader { Reader(self) }

    public init(url: String, format: String, headers: [String: String] = [:],
                directory: URL = Downloader.cacheDirectory,
                configuration: URLSessionConfiguration = NetworkMode.current.sessionConfiguration()) throws {
        guard let source = URL(string: url), source.host != nil,
              ["http", "https"].contains(source.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent(Downloader.cacheFilename(url: url, key: "", format: format, headers: headers))
        partialURL = directory.appendingPathComponent(".stream-\(UUID().uuidString).part")
        let cachedSize = (try? cacheURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]))
        let cached = cachedSize?.isRegularFile == true && (cachedSize?.fileSize ?? 0) > 4096
        descriptor = Darwin.open((cached ? cacheURL : partialURL).path, cached ? O_RDONLY : (O_CREAT | O_EXCL | O_RDWR), 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        super.init()
        if cached {
            total = Int64(cachedSize?.fileSize ?? 0); intervals = [0..<total]; done = true
            return
        }
        var request = URLRequest(url: source)
        request.setValue("Mozilla/5.0 PureListen", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.timeoutInterval = 30
        self.request = request
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: request)
        transfers[task.taskIdentifier] = Transfer(offset: 0)
        task.resume()
    }

    deinit {
        session?.invalidateAndCancel()
        Darwin.close(descriptor)
        try? FileManager.default.removeItem(at: partialURL)
    }

    public func cancel() {
        condition.lock(); cancelled = true; condition.broadcast(); condition.unlock()
        session?.invalidateAndCancel()
        try? FileManager.default.removeItem(at: partialURL)
    }
    private func wake() { condition.lock(); condition.broadcast(); condition.unlock() }

    func length(reader: Reader) throws -> Int64 {
        condition.lock(); defer { condition.unlock() }
        while total == 0 && !done {
            try check(reader)
            _ = condition.wait(until: Date().addingTimeInterval(0.1))
        }
        try check(reader)
        return total
    }
    private func check(_ reader: Reader) throws {
        try reader.check()
        if cancelled { throw CancellationError() }
        if let failure { throw failure }
        if !done && Date().timeIntervalSince(lastActivity) > 35 { throw URLError(.timedOut) }
    }
    private func read(_ offset: Int64, _ count: Int, reader: Reader) throws -> Data {
        guard offset >= 0, count >= 0 else { throw URLError(.cannotDecodeContentData) }
        let length = try length(reader: reader)
        let wanted = Int(min(Int64(count), max(0, length - offset)))
        guard wanted > 0 else { return Data() }
        let end = offset + Int64(wanted)
        condition.lock()
        do {
            while !intervals.contains(where: { $0.lowerBound <= offset && $0.upperBound >= end }) {
                try check(reader)
                if done { throw URLError(.cannotDecodeContentData) }
                // 顺序下载负责连续缓存，远处的读取（文件尾/拖动）另发有界 Range。
                if offset > sequentialBytes + 262_144 { requestRange(offset..<min(length, max(end, offset + 262_144))) }
                _ = condition.wait(until: Date().addingTimeInterval(0.1))
            }
            try check(reader)
            condition.unlock()
        } catch { condition.unlock(); throw error }
        var data = Data(count: wanted)
        let received = data.withUnsafeMutableBytes { Darwin.pread(descriptor, $0.baseAddress, wanted, off_t(offset)) }
        guard received == wanted else { throw POSIXError(.EIO) }
        return data
    }

    private func requestRange(_ range: Range<Int64>) {
        guard rangesSupported, !transfers.values.contains(where: { $0.range?.overlaps(range) == true }),
              var request, let session else { return }
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        if let entityTag { request.setValue(entityTag, forHTTPHeaderField: "If-Range") }
        let task = session.dataTask(with: request)
        transfers[task.taskIdentifier] = Transfer(offset: range.lowerBound, range: range)
        task.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        condition.lock(); defer { condition.unlock() }
        guard var transfer = transfers[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); return
        }
        let mime = http.mimeType?.lowercased() ?? ""
        guard !mime.hasPrefix("text/"), !mime.contains("json"), !mime.contains("xml") else {
            failure = URLError(.cannotDecodeContentData); condition.broadcast(); completionHandler(.cancel); return
        }
        if let range = transfer.range {
            let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            let expected = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(total)"
            guard http.statusCode == 206, contentRange == expected,
                  entityTag == nil || http.value(forHTTPHeaderField: "ETag") == entityTag else {
                // 不支持 Range 时仍可等待顺序数据，绝不将整个响应写到错误偏移。
                rangesSupported = false
                completionHandler(.cancel); return
            }
        } else {
            guard http.statusCode == 200 else {
                failure = URLError(.badServerResponse); condition.broadcast(); completionHandler(.cancel); return
            }
            total = max(0, http.expectedContentLength)
            entityTag = http.value(forHTTPHeaderField: "ETag")
        }
        transfer.accepted = true; transfers[dataTask.taskIdentifier] = transfer
        lastActivity = Date(); condition.broadcast(); completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        condition.lock(); defer { condition.unlock() }
        guard !cancelled, failure == nil, var transfer = transfers[dataTask.taskIdentifier], transfer.accepted else { return }
        let start = transfer.offset
        let written = data.withUnsafeBytes { Darwin.pwrite(descriptor, $0.baseAddress, data.count, off_t(start)) }
        guard written == data.count else { failure = POSIXError(.EIO); condition.broadcast(); return }
        transfer.offset += Int64(data.count)
        transfers[dataTask.taskIdentifier] = transfer
        if transfer.range == nil { sequentialBytes = transfer.offset }
        intervals.append(start..<transfer.offset)
        intervals.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int64>] = []
        for range in intervals {
            if let last = merged.last, last.upperBound >= range.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        intervals = merged; lastActivity = Date(); condition.broadcast()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        condition.lock(); defer { condition.unlock() }
        guard let transfer = transfers.removeValue(forKey: task.taskIdentifier) else { return }
        guard transfer.range == nil else { condition.broadcast(); return }
        defer { session.finishTasksAndInvalidate(); condition.broadcast() }
        guard !cancelled else { return }
        if let error { if failure == nil { failure = error }; return }
        if total == 0 { total = sequentialBytes }
        guard failure == nil, total > 4096, sequentialBytes == total else {
            failure = URLError(.cannotDecodeContentData); return
        }
        do {
            // 另一个相同请求已发布缓存时保留那个完整文件；当前 fd 仍可继续读。
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                let size = (try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size == total { try FileManager.default.removeItem(at: partialURL) }
                else { _ = try FileManager.default.replaceItemAt(cacheURL, withItemAt: partialURL) }
            } else { try FileManager.default.moveItem(at: partialURL, to: cacheURL) }
            done = true
        } catch { failure = error }
    }
}

private extension Range where Bound == Int64 {
    var count64: Int64 { upperBound - lowerBound }
}
