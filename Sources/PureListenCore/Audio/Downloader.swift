import Foundation

/// 歌曲下载/缓存: ~/Library/Caches/PureListen/<md5>.<ext>
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
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    public static func clearCache() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files { try? FileManager.default.removeItem(at: url) }
    }

    /// 已缓存则直接返回; 否则下载完整文件(无损播放需要完整的 FLAC 头与帧)。
    public static func ensureLocal(url: String, key: String, format: String,
                            headers: [String: String] = [:],
                            progress: ((Double) -> Void)? = nil) async throws -> URL {
        let ext = format.isEmpty ? "audio" : format
        let filename = "\(key.isEmpty ? UUID().uuidString : key).\(ext)"
        let destination = cacheDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            progress?(1)
            return destination
        }

        guard let source = URL(string: url) else {
            throw URLError(.badURL)
        }
        let tmp = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: tmp)

        var request = URLRequest(url: source)
        if headers.isEmpty {
            request.setValue("Mozilla/5.0 (Macintosh; ARM64 Mac OS X 10_15_7) NetEaseMusic/PureListen",
                             forHTTPHeaderField: "User-Agent")
        } else {
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        }
        let (temporaryURL, response) = try await download(request: request, to: tmp, progress: progress)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.badServerResponse)
        }
        // 后端偶尔对无版权歌曲返回占位内容, 检查文件大小合理性。
        let attributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 4096 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.zeroByteResource)
        }
        if (try? FileManager.default.moveItem(at: temporaryURL, to: destination)) == nil {
            try? FileManager.default.removeItem(at: tmp)
        }
        progress?(1)
        return destination
    }

    /// 网易 CDN 直连会话(绕过系统代理)。
    static let directSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// 整段下载到临时文件(无损文件几十 MB, 内存可承受; 完成后落盘)。
    private static func download(request: URLRequest, to destination: URL,
                                 progress: ((Double) -> Void)?) async throws -> (URL, URLResponse) {
        progress?(0.1)
        let (data, response) = try await directSession.data(for: request)
        progress?(0.9)
        try data.write(to: destination, options: .atomic)
        return (destination, response)
    }
}
