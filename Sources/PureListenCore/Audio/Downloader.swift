import Foundation
import CryptoKit

/// 完整下载到磁盘后才发布缓存；缓存名不暴露签名 URL 或 Cookie。
public enum Downloader {
    public static var cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PureListen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static func cacheSizeBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    public static func clearCache() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files { try? FileManager.default.removeItem(at: url) }
    }

    public static func ensureLocal(url: String, key: String, format: String,
                                   headers: [String: String] = [:],
                                   progress: ((Double) -> Void)? = nil) async throws -> URL {
        let session = URLSession(configuration: NetworkMode.current.sessionConfiguration())
        defer { session.invalidateAndCancel() }
        return try await ensureLocal(url: url, key: key, format: format, headers: headers,
                                     progress: progress, directory: cacheDirectory, session: session)
    }

    static func cacheFilename(url: String, key: String, format: String, headers: [String: String]) -> String {
        // 包含完整地址与请求头，避免不同站点、账号和音质的同名文件串用。
        let identity = [url, key, HTTPTask.cookieHeader(headers)].joined(separator: "\0")
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let ext = format.lowercased()
        let safeExtension = !ext.isEmpty && ext.count <= 10 && ext.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0)
        } ? ext : "audio"
        return "v2-\(digest).\(safeExtension)"
    }

    private static func validCache(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { return false }
        return (values.fileSize ?? 0) > 4096
    }

    /// 内部可注入隔离目录与会话，回归测试无需用户缓存或外网。
    static func ensureLocal(url: String, key: String, format: String,
                            headers: [String: String] = [:], progress: ((Double) -> Void)? = nil,
                            directory: URL, session: URLSession) async throws -> URL {
        try Task.checkCancellation()
        guard let source = URL(string: url), source.host?.isEmpty == false,
              ["http", "https"].contains(source.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(cacheFilename(url: url, key: key, format: format, headers: headers))
        if validCache(destination) { progress?(1); return destination }
        try? FileManager.default.removeItem(at: destination)

        var request = URLRequest(url: source)
        request.setValue("Mozilla/5.0 (Macintosh; ARM64 Mac OS X 10_15_7) NetEaseMusic/PureListen",
                         forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        progress?(0)
        let (temporaryURL, response) = try await session.download(for: request, delegate: DownloadProgress(progress))
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let type = http.mimeType?.lowercased() ?? ""
        guard !type.hasPrefix("text/"), !type.contains("json"), !type.contains("xml") else { throw URLError(.cannotDecodeContentData) }
        guard validCache(temporaryURL) else { throw URLError(.zeroByteResource) }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            // 同一首歌并发下载时，另一个请求可能已提交完整文件。
            guard validCache(destination) else { throw error }
        }
        progress?(1)
        return destination
    }

    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let callback: ((Double) -> Void)?
        init(_ callback: ((Double) -> Void)?) { self.callback = callback }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {}
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            callback?(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }
}
