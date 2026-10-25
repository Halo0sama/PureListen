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

    public init(id: String = UUID().uuidString, title: String, artist: String,
                source: Source, downloadURL: String, format: String,
                headers: [String: String] = [:], coverURL: String = "",
                detail: String = "", neteaseID: Int = 0) {
        self.id = id; self.title = title; self.artist = artist; self.source = source
        self.downloadURL = downloadURL; self.format = format; self.headers = headers
        self.coverURL = coverURL; self.detail = detail; self.neteaseID = neteaseID
    }
}

/// 解析用户输入(歌曲ID/链接/BV号/直链)为可播放条目。
public enum SourceResolver {
    static let browserUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"

    public static func isDirectAudioURL(_ text: String) -> Bool {
        guard text.hasPrefix("http://") || text.hasPrefix("https://") else { return false }
        let lower = text.lowercased()
        if text.contains("music.163.com") || text.contains("bilibili.com") || text.contains("b23.tv") {
            return false
        }
        return [".flac", ".mp3", ".m4a", ".wav", ".aac", ".ogg", ".ape", ".aiff"].contains {
            lower.contains($0)
        }
    }

    /// 解析输入文本; 返回 nil 表示无法识别。
    public static func classify(_ raw: String) -> (kind: String, value: String)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 网易: song?id=123 或纯数字
        if let range = text.range(of: "song?id="), let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                return ("netease", id)
            }
        }
        if let n = Int(text), (1...9_999_999_999).contains(n) {
            return ("netease", String(n))
        }
        if text.hasPrefix("http") && text.contains("163.com") {
            return ("netease", text)   // 交给调用方展开
        }

        // B站: BV号 / av号 / 链接
        if text.hasPrefix("BV") && text.count >= 10 { return ("bilibili", text) }
        if text.lowercased().hasPrefix("av"), let av = Int(text.dropFirst(2)) {
            return ("bilibili", "av\(av)")
        }
        if text.contains("bilibili.com") || text.contains("b23.tv") {
            return ("bilibili", text)
        }

        // 直链音频
        if isDirectAudioURL(text) { return ("direct", text) }

        return nil
    }

    // MARK: - 网易

    public static func resolveNetease(id: Int, client: NCClient, level: NCLevel) async throws -> PlayableItem {
        let detail = try await client.songDetail(id: id)
        var url = try await client.songURL(id: id, level: level)
        if url == nil {
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
            detail: "\(url.level) · \(url.br / 1000)kbps",
            neteaseID: id)
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
    static func expandShortLink(_ url: String) async -> String {
        guard url.contains("b23.tv") else { return url }
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-s", "-o", "/dev/null", "-w", "%{url_effective}", "-L", "-m", "15", url,
                          "-A", browserUA]
        let pipe = Pipe()
        curl.standardOutput = pipe
        curl.standardError = Pipe()
        try? curl.run()
        curl.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.isEmpty ? url : out
    }

    public static func resolveBilibili(_ input: String, pageIndex: Int? = nil,
                                       bili: BiliClient? = nil) async throws -> [PlayableItem] {
        var headers = ["User-Agent": BiliClient.UA, "Referer": "https://www.bilibili.com/"]
        if let bili, bili.isLoggedIn {
            headers["Cookie"] = HTTPTask.cookieHeader(bili.cookies)
        }
        var text = input
        if text.contains("b23.tv") {
            text = await expandShortLink(text)
        }
        // 提取 BV 号或 av 号
        var bvid: String?
        if let r = text.range(of: "BV[0-9A-Za-z]{10}") { bvid = String(text[r]) }
        else if let r = text.range(of: "av[0-9]+", options: .caseInsensitive) {
            bvid = String(text[r].lowercased())
        } else if text.hasPrefix("BV") { bvid = text }
        guard let bv = bvid else {
            throw NSError(domain: "Bili", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "未识别到 BV/av 号"])
        }
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

        var items: [PlayableItem] = []
        for (index, page) in pages.enumerated() {
            if let pageIndex, index != pageIndex - 1 { continue }
            let play = try await httpGetJSON(
                "https://api.bilibili.com/x/player/playurl?\(query)&cid=\(page.cid)&fnval=16&qn=64&try_look=1",
                headers: headers)
            guard let playData = play["data"] as? [String: Any] else { continue }
            var audioURL: String?
            var quality = ""
            if let dash = playData["dash"] as? [String: Any],
               let audio = dash["audio"] as? [[String: Any]] {
                // 按 id(码率档) 降序取最好音质: 30280=192k 30232=132k 30216=64k
                let best = audio.sorted { ($0["id"] as? Int ?? 0) > ($1["id"] as? Int ?? 0) }.first
                if let baseUrl = best?["baseUrl"] as? String, !baseUrl.isEmpty {
                    audioURL = baseUrl
                    switch best?["id"] as? Int {
                    case 30280: quality = "192kbps"
                    case 30232: quality = "132kbps"
                    case 30216: quality = "64kbps"
                    default: quality = ""
                    }
                }
            }
            if audioURL == nil, let durl = playData["durl"] as? [[String: Any]],
               let first = durl.first, let u = first["url"] as? String {
                audioURL = u   // mp4 渐进流兜底
                quality = "mp4"
            }
            guard let audioURL else { continue }
            let suffix = audioURL.contains(".m4a") ? "m4a" : "m4a"
            items.append(PlayableItem(
                title: title,
                artist: owner,
                source: .bilibili,
                downloadURL: audioURL,
                format: suffix,
                headers: headers,
                coverURL: pic,
                detail: (page.part.isEmpty ? "" : page.part + " · ") + quality + " · DASH音频"))
        }
        if items.isEmpty {
            throw NSError(domain: "Bili", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "未取到音频流"])
        }
        return items
    }

    // MARK: - 直链

    public static func resolveDirect(_ url: String) -> PlayableItem {
        let lower = url.lowercased()
        var format = "mp3"
        for ext in ["flac", "m4a", "wav", "aac", "ogg", "ape", "aiff", "mp3"] {
            if lower.contains(".\(ext)") { format = ext; break }
        }
        let name = url.split(separator: "/").last.map(String.init) ?? url
        return PlayableItem(title: name, artist: "直链",
                            source: .direct, downloadURL: url, format: format)
    }
}
