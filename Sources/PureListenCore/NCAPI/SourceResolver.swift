import Foundation

/// 统一播放源: 网易歌曲 / B站视频 / 直链。
public struct PlayableItem: Identifiable, Equatable {
    public enum Source: String {
        case netease = "网易云"
        case bilibili = "哔哩哔哩"
        case direct = "直链"
    }

    public var id: String
    public var title: String
    public var artist: String
    public var source: Source
    public var downloadURL: String
    public var format: String             // flac / m4a / mp3 ...
    public var headers: [String: String]  // 下载所需头(B站需 Referer)
    public var coverURL: String
    /// 附加描述(B站分P、码率等)。
    public var detail: String
    /// 网易歌曲 id(联动收藏等), 非网易为 0。
    public var neteaseID: Int
    public var bitrate: Int
    public var codec: String
    public var quality: String
    public var sizeBytes: Int64

    public init(id: String = UUID().uuidString, title: String, artist: String,
                source: Source, downloadURL: String, format: String,
                headers: [String: String] = [:], coverURL: String = "",
                detail: String = "", neteaseID: Int = 0,
                bitrate: Int = 0, codec: String = "", quality: String = "", sizeBytes: Int64 = 0) {
        self.id = id; self.title = title; self.artist = artist; self.source = source
        self.downloadURL = downloadURL; self.format = format; self.headers = headers
        self.coverURL = coverURL; self.detail = detail; self.neteaseID = neteaseID
        self.bitrate = bitrate; self.codec = codec; self.quality = quality; self.sizeBytes = sizeBytes
    }
}

/// 解析用户输入(歌曲ID/链接/BV号/直链)为可播放条目。
public enum SourceResolver {
    static let browserUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"

    private static let audioExtensions = ["flac", "mp3", "m4a", "wav", "aac", "ogg", "ape", "aiff"]

    private static func matchesHost(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    /// 从分享文案中提取链接；直接粘贴的 URL 保留完整签名参数。
    static func inputURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if !text.contains(where: { $0.isWhitespace }), let url = URL(string: text),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            candidate = text
        } else {
            guard let range = text.range(of: #"https?://[^\s<>"「」]+"#, options: .regularExpression) else { return nil }
            candidate = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "，。！；）】>"))
        }
        guard let url = URL(string: candidate), url.host != nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    public static func isDirectAudioURL(_ text: String) -> Bool {
        guard let url = inputURL(text) else { return false }
        let host = url.host?.lowercased() ?? ""
        guard !matchesHost(host, domain: "music.163.com"),
              !matchesHost(host, domain: "bilibili.com"), !matchesHost(host, domain: "b23.tv") else { return false }
        return audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func bilibiliIdentifier(in text: String) -> String? {
        if let range = text.range(of: #"(?<![0-9A-Za-z])BV[0-9A-Za-z]{10}(?![0-9A-Za-z])"#, options: .regularExpression) {
            return String(text[range])
        }
        if let range = text.range(of: #"(?i)(?<![0-9A-Za-z])av[1-9][0-9]*(?![0-9A-Za-z])"#, options: .regularExpression) {
            return String(text[range]).lowercased()
        }
        return nil
    }

    /// 解析输入文本；仅对真实站点识别站内链接。
    public static func classify(_ raw: String) -> (kind: String, value: String)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let n = Int(text), (1...9_999_999_999).contains(n) { return ("netease", String(n)) }
        if let url = inputURL(text) {
            let host = url.host?.lowercased() ?? ""
            if matchesHost(host, domain: "music.163.com") {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let fragment = components?.fragment.flatMap { URLComponents(string: $0) }
                let song = fragment?.path == "/song" || fragment?.path == "song" ? fragment : components
                guard song?.path == "/song" || song?.path == "song",
                      let value = song?.queryItems?.first(where: { $0.name == "id" })?.value,
                      let id = Int(value), id > 0 else { return nil }
                return ("netease", String(id))
            }
            if matchesHost(host, domain: "bilibili.com") || matchesHost(host, domain: "b23.tv") {
                return ("bilibili", url.absoluteString)
            }
            if isDirectAudioURL(url.absoluteString) { return ("direct", url.absoluteString) }
            return nil
        }
        if let identifier = bilibiliIdentifier(in: text) { return ("bilibili", identifier) }
        return nil
    }

    // MARK: - 网易

    public static func resolveNetease(id: Int, client: NCClient, level: NCLevel) async throws -> PlayableItem {
        let detail = try await client.songDetail(id: id)
        var url = try await client.songURL(id: id, level: level)
        if url?.url?.isEmpty != false {
            url = try await client.songURLFallback(id: id, level: level)
        }
        guard let url, let link = url.url, !link.isEmpty else {
            throw NSError(domain: "Source", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "取不到音源(无版权或需 VIP)"])
        }
        let format = url.format.isEmpty ? "mp3" : url.format
        let track = detail?.first
        return PlayableItem(
            title: track?.name ?? "歌曲 \(id)",
            artist: track?.artists ?? "",
            source: .netease,
            downloadURL: link,
            format: format,
            coverURL: track?.coverURL ?? "",
            detail: track?.album ?? "",
            neteaseID: id, bitrate: url.br, quality: url.level, sizeBytes: url.sizeBytes)
    }

    // MARK: - B站

    struct BiliPage {
        var cid: Int
        var part: String
    }

    static func httpGetJSON(_ url: String, headers: [String: String]) async throws -> [String: Any] {
        try await HTTPTask.get(url: url, headers: headers).json
    }

    /// 展开短链(b23.tv)获取 BV 号。
    static func expandShortLink(_ url: String) async throws -> String {
        let response = try await CurlTransport.request(url: url, headers: ["User-Agent": browserUA], timeout: 15)
        return response.effectiveURL
    }

    public static func resolveBilibili(_ input: String, pageIndex: Int? = nil,
                                       bili: BiliClient? = nil,
                                       quality preference: BiliAudioQuality = .high) async throws -> [PlayableItem] {
        var headers = ["User-Agent": BiliClient.UA, "Referer": "https://www.bilibili.com/"]
        if let bili, bili.isLoggedIn {
            headers["Cookie"] = HTTPTask.cookieHeader(bili.cookies)
        }
        var text = inputURL(input)?.absoluteString ?? input
        if let host = URL(string: text)?.host?.lowercased(), matchesHost(host, domain: "b23.tv") {
            text = try await expandShortLink(text)
        }
        guard let bv = bilibiliIdentifier(in: URL(string: text)?.path ?? text) else {
            throw NSError(domain: "Bili", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "未识别到 BV/av 号"])
        }
        let requestedPage = pageIndex ?? URLComponents(string: text)?.queryItems?
            .first(where: { $0.name == "p" })?.value.flatMap(Int.init)
        let query = bv.hasPrefix("av")
            ? "aid=\(bv.dropFirst(2))"
            : "bvid=\(bv)"

        let view = try await httpGetJSON("https://api.bilibili.com/x/web-interface/view?\(query)", headers: headers)
        guard let data = view["data"] as? [String: Any],
              let cid = data["cid"] as? Int else {
            throw NSError(domain: "Bili", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "视频信息获取失败(\(view["code"] ?? "?"))"])
        }
        let title = (data["title"] as? String) ?? bv
        let owner = ((data["owner"] as? [String: Any])?["name"] as? String) ?? ""
        let pic = (data["pic"] as? String) ?? ""

        var pages: [BiliPage] = []
        if let rawPages = data["pages"] as? [[String: Any]] {
            pages = rawPages.compactMap { page in
                guard let c = page["cid"] as? Int else { return nil }
                return BiliPage(cid: c, part: (page["part"] as? String) ?? "P?")
            }
        }
        if pages.isEmpty { pages = [BiliPage(cid: cid, part: "")] }

        if let requestedPage, !(1...pages.count).contains(requestedPage) {
            throw NSError(domain: "Bili", code: 4, userInfo: [NSLocalizedDescriptionKey: "分 P 编号超出范围"])
        }
        var items: [PlayableItem] = []
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            if let requestedPage, index != requestedPage - 1 { continue }
            let play = try await httpGetJSON(
                "https://api.bilibili.com/x/player/playurl?\(query)&cid=\(page.cid)&fnval=4048&fnver=0&qn=127&fourk=1",
                headers: headers)
            guard let playData = play["data"] as? [String: Any] else { continue }
            var audioURL: String?
            var quality = ""
            var bitrate = 0
            var codec = ""
            if let dash = playData["dash"] as? [String: Any],
               let stream = biliAudio(in: dash, quality: preference) {
                audioURL = stream.url
                quality = stream.quality
                bitrate = stream.bitrate
                codec = stream.codec
            }
            if audioURL == nil, let durl = playData["durl"] as? [[String: Any]],
               let first = durl.first, let u = first["url"] as? String {
                audioURL = u   // mp4 渐进流兜底
                quality = "mp4"
            }
            guard let audioURL else { continue }
            items.append(PlayableItem(
                title: title,
                artist: owner,
                source: .bilibili,
                downloadURL: audioURL,
                format: codec.lowercased() == "flac" ? "flac" : (quality == "mp4" ? "mp4" : "m4a"),
                headers: headers,
                coverURL: pic,
                detail: page.part,
                bitrate: bitrate, codec: codec, quality: quality))
        }
        if items.isEmpty {
            throw NSError(domain: "Bili", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "未取到音频流"])
        }
        return items
    }

    // MARK: - 直链

    public static func resolveDirect(_ url: String) -> PlayableItem {
        let source = URL(string: url)
        let ext = source?.pathExtension.lowercased() ?? ""
        let format = audioExtensions.contains(ext) ? ext : "mp3"
        let name = source?.lastPathComponent ?? url
        return PlayableItem(title: name, artist: "直链",
                            source: .direct, downloadURL: url, format: format)
    }
}
