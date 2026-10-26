import Foundation

/// B 站客户端: 扫码登录(与官方网页同款) + 带 Cookie 的 API。
public final class BiliClient {
    public static let UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
    static let apiHeaders: [String: String] = [
        "User-Agent": UA,
        "Referer": "https://www.bilibili.com/",
        "Origin": "https://www.bilibili.com",
    ]

    public private(set) var cookies: [String: String]

    public init(cookies: [String: String] = [:]) {
        self.cookies = cookies
    }

    public var isLoggedIn: Bool { cookies["SESSDATA"]?.isEmpty == false }

    var cookieHeader: String {
        HTTPTask.cookieHeader(cookies)
    }

    func apiHeaders(withCookie: Bool) -> [String: String] {
        var headers = Self.apiHeaders
        if withCookie, !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }

    // MARK: - 扫码登录

    /// NeriPlayer 同款请求头: 会话连续性(Cookie) + 精确 Referer 是拿到 Set-Cookie 的关键。
    private var qrSessionCookies: [String: String] = [:]

    private func qrLoginHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Referer": "https://passport.bilibili.com/login",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ]
        let cookie = qrSessionCookies.filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        return headers
    }

    private func absorbCookies(_ setCookies: [String: String]) {
        for (name, value) in setCookies {
            if value.isEmpty { qrSessionCookies.removeValue(forKey: name) }
            else { qrSessionCookies[name] = value }
        }
    }

    /// 生成登录二维码, 返回 (二维码内容, qrcode_key)。
    public func createLoginQR() async throws -> (url: String, key: String) {
        qrSessionCookies.removeAll()
        let resp = try await HTTPTask.get(
            url: "https://passport.bilibili.com/x/passport-login/web/qrcode/generate",
            headers: qrLoginHeaders())
        absorbCookies(resp.setCookies)
        NCLog.log("B站 generate 收到 Cookie: \(resp.setCookies.keys.sorted().joined(separator: ","))")
        guard let data = resp.json["data"] as? [String: Any],
              let url = data["url"] as? String,
              let key = data["qrcode_key"] as? String else {
            throw NSError(domain: "Bili", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "生成二维码失败"])
        }
        return (url, key)
    }

    /// 轮询扫码状态(真实状态在 data.code, 外层 code 恒为 0):
    /// 0=成功(Cookie 已合并) / 86090=已扫码待确认 / 86101=等待 / 86038=过期。
    @discardableResult
    public func pollLoginQR(key: String) async throws -> Int {
        let resp = try await HTTPTask.get(
            url: "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=\(key)",
            headers: qrLoginHeaders())
        absorbCookies(resp.setCookies)
        let data = resp.json["data"] as? [String: Any]
        let code = (data?["code"] as? Int) ?? 86101
        if code == 0 {
            NCLog.log("B站 poll setCookies: \(resp.setCookies.keys.sorted().joined(separator: ","))")
            // SESSDATA 应随成功响应下发(NeriPlayer 同款路径)
            for (name, value) in qrSessionCookies where !value.isEmpty {
                cookies[name] = value
            }
        }
        guard code == 0 else { return code }

        // 成功: 完整记录响应结构, 多路径捕获 Cookie
        NCLog.log("B站登录成功响应 data 键: \(data?.keys.sorted().joined(separator: ",") ?? "无")")
        NCLog.log("B站 crossDomain 地址存在: \(data?["url"] as? String != nil)")
        NCLog.log("B站 响应头Set-Cookie数: \(resp.setCookies.count)")

        // 0) 新版接口: data.cookie_info.cookies = [{name, value}]
        if let cookieInfo = data?["cookie_info"] as? [String: Any],
           let cookieArray = cookieInfo["cookies"] as? [[String: Any]] {
            for cookie in cookieArray {
                if let name = cookie["name"] as? String,
                   let value = cookie["value"] as? String, !value.isEmpty {
                    cookies[name] = value
                }
            }
            NCLog.log("B站 cookie_info 捕获: \(cookies.keys.sorted().joined(separator: ","))")
        }

        // 1) 响应头 Set-Cookie
        for (name, value) in resp.setCookies where !value.isEmpty {
            cookies[name] = value
        }

        // 2) data.url 查询参数(手工解析, 不依赖 URLComponents)
        var crossURL: String?
        if let urlStr = data?["url"] as? String, !urlStr.isEmpty {
            crossURL = urlStr
            if let qIndex = urlStr.firstIndex(of: "?") {
                let query = String(urlStr[urlStr.index(after: qIndex)...])
                for pair in query.split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    guard kv.count == 2 else { continue }
                    let name = String(kv[0])
                    let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    if ["SESSDATA", "DedeUserID", "DedeUserID__ckMd5", "bili_jct", "Expires"].contains(name),
                       !value.isEmpty {
                        cookies[name] = value
                    }
                }
            }
        }
        NCLog.log("B站 url参数+响应头捕获后: \(cookies.keys.sorted().joined(separator: ","))")

        // 3) 访问 crossDomain ticket 地址换取 Cookie(官方姿势: Win UA + passport Referer + 不跟随重定向)
        if let crossURL {
            let winUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            let crossHeaders = ["User-Agent": winUA,
                                "Referer": "https://passport.bilibili.com/"]
            if let cross = try? await HTTPTask.get(url: crossURL, headers: crossHeaders,
                                                   followRedirects: false) {
                NCLog.log("B站 crossDomain 访问: HTTP \(cross.statusCode) Set-Cookie: \(cross.setCookies.keys.sorted().joined(separator: ","))")
                for (name, value) in cross.setCookies where !value.isEmpty {
                    cookies[name] = value
                }
            }
        }
        NCLog.log("B站登录 Cookie 最终: \(cookies.keys.sorted().joined(separator: ","))")
        return code
    }

    /// 登录用户信息。
    public func account() async throws -> (uname: String, mid: Int)? {
        let resp = try await HTTPTask.get(
            url: "https://api.bilibili.com/x/web-interface/nav",
            headers: apiHeaders(withCookie: true))
        guard let data = resp.json["data"] as? [String: Any],
              let mid = data["mid"] as? Int else { return nil }
        let uname = (data["uname"] as? String) ?? "B站用户"
        return (uname, mid)
    }

    public func logout() {
        cookies.removeAll()
    }

    /// 注入 WebView 登录收割的 Cookie(网页登录兜底, NeriPlayer 同款思路)。
    public func applyWebLoginCookies(_ webCookies: [String: String]) {
        for (name, value) in webCookies where !value.isEmpty {
            cookies[name] = value
        }
    }

    // MARK: - 收藏夹

    public struct FavFolder: Identifiable, Equatable {
        public var id: Int
        public var title: String
        public var mediaCount: Int

        public init(id: Int, title: String, mediaCount: Int) {
            self.id = id
            self.title = title
            self.mediaCount = mediaCount
        }
    }

    public struct FavVideo: Identifiable, Equatable {
        public var id: Int
        public var bvid: String
        public var title: String
        public var cover: String
        public var upper: String
        public var durationSeconds: Int

        public init(id: Int, bvid: String, title: String, cover: String, upper: String, durationSeconds: Int) {
            self.id = id; self.bvid = bvid; self.title = title; self.cover = cover
            self.upper = upper; self.durationSeconds = durationSeconds
        }
    }

    /// 收藏夹列表(需要已登录)。
    public func favoriteFolders(mid: Int) async throws -> [FavFolder] {
        let resp = try await HTTPTask.get(
            url: "https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=\(mid)",
            headers: apiHeaders(withCookie: true))
        guard let data = resp.json["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else { return [] }
        return list.compactMap { folder in
            guard let id = folder["id"] as? Int else { return nil }
            return FavFolder(id: id,
                             title: (folder["title"] as? String) ?? "收藏夹",
                             mediaCount: (folder["media_count"] as? Int) ?? 0)
        }
    }

    /// 收藏夹内视频(分页)。
    public func favoriteVideos(folderId: Int, page: Int,
                               pageSize: Int = 20) async throws -> (videos: [FavVideo], hasMore: Bool) {
        let resp = try await HTTPTask.get(
            url: "https://api.bilibili.com/x/v3/fav/resource/list?media_id=\(folderId)&pn=\(page)&ps=\(pageSize)&order=mtime&type=0&tid=0&keyword=",
            headers: apiHeaders(withCookie: true))
        guard let data = resp.json["data"] as? [String: Any] else { return ([], false) }
        let medias = (data["medias"] as? [[String: Any]]) ?? []
        let videos = medias.compactMap { media -> FavVideo? in
            guard let bvid = media["bvid"] as? String, !bvid.isEmpty else { return nil }
            let duration: Int
            if let d = media["duration"] as? Int { duration = d }
            else if let d = media["duration"] as? Double { duration = Int(d) }
            else { duration = 0 }
            return FavVideo(id: media["id"] as? Int ?? bvid.hashValue,
                            bvid: bvid,
                            title: (media["title"] as? String) ?? bvid,
                            cover: (media["cover"] as? String) ?? "",
                            upper: ((media["upper"] as? [String: Any])?["name"] as? String) ?? "",
                            durationSeconds: duration)
        }
        let more = (data["has_more"] as? Bool) ?? false
        return (videos, more)
    }
}
