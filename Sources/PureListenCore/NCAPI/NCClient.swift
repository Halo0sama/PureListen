import Foundation

/// 网易云音乐 HTTP 客户端: weapi(music.163.com) + eapi(interface3.music.163.com)。
///
/// Cookie 全程手动管理: 网易的登录 Cookie(MUSIC_U) 带 Version=1 属性,
/// CFNetwork 的 HTTPCookieStorage 会静默丢弃它, 必须手动解析 Set-Cookie。
public final class NCClient {
    static let domain = "https://music.163.com"
    static let apiDomain = "https://interface3.music.163.com"

    /// 持久化的 Cookie(含 MUSIC_U)。
    private var storedCookies: [String: String]
    private let cookieLock = NSLock()
    public var cookies: [String: String] {
        cookieLock.lock()
        defer { cookieLock.unlock() }
        return storedCookies
    }
    /// 持久化设备 id(网易风控用)。
    public let deviceId: String
    public var isLoggedIn: Bool { cookies["MUSIC_U"]?.isEmpty == false }

    /// sessionOverride 保留兼容；网络策略由 NetworkMode 统一管理。
    public init(cookies: [String: String] = [:], deviceId: String? = nil, sessionOverride: String? = nil) {
        self.storedCookies = cookies
        if let deviceId, !deviceId.isEmpty {
            self.deviceId = deviceId
        } else {
            self.deviceId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        _ = sessionOverride   // 传输层已统一为 curl, 不再需要会话区分
        seedRiskControlCookies()
    }

    /// 与官方/参照实现一致的风控 Cookie 配方(一次性生成, 随 cookies 持久化)。
    private func seedRiskControlCookies() {
        let ms = String(Int(Date().timeIntervalSince1970 * 1000))
        if storedCookies["_ntes_nuid"] == nil {
            let hexChars = Array("0123456789abcdef")
            let nuid = String((0..<64).map { _ in hexChars.randomElement()! })
            storedCookies["_ntes_nuid"] = nuid
            storedCookies["_ntes_nnid"] = "\(nuid),\(ms)"
        }
        if storedCookies["WNMCID"] == nil {
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            let rand6 = String((0..<6).map { _ in letters.randomElement()! })
            storedCookies["WNMCID"] = "\(rand6).\(ms).01.0"
        }
    }

    // MARK: - Cookie 头构造

    /// isLogin: 登录相关接口(路径含 login)不应携带 NMTID(参照实现行为)。
    private func effectiveCookies(isLogin: Bool) -> [String: String] {
        var all = cookies
        all["__remember_me"] = "true"
        all["ntes_kaola_ad"] = "1"
        all["WEVNSM"] = "1.0.0"
        all["os"] = "pc"
        all["appver"] = "3.1.17.204416"
        all["osver"] = "Microsoft-Windows-10-Professional-build-19045-64bit"
        all["channel"] = "netease"
        all["deviceId"] = deviceId
        if isLogin { all.removeValue(forKey: "NMTID") }
        return all.filter { !$0.value.isEmpty }
    }

    /// 调试用: 当前会发出的完整 Cookie 头。
    public func debugCookieHeader(isLogin: Bool = false) -> String {
        cookieHeader(isLogin: isLogin)
    }

    private func cookieHeader(isLogin: Bool = false) -> String {
        effectiveCookies(isLogin: isLogin).sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    // MARK: - Set-Cookie 手动解析

    // MARK: - curl 传输

    /// 执行 curl, 返回 (body, 原始响应头文本, http状态码)。响应头含每一次重定向跳转。
    private func curlExecute(url: URL, method: String, headers: [String: String],
                             body: String?) async throws -> (Data, String, Int) {
        let response = try await CurlTransport.request(method: method, url: url.absoluteString,
                                                       headers: headers, body: body)
        return (response.data, response.headers, response.statusCode)
    }

    /// 从 curl 的原始响应头文本(-D 输出, 含每一次重定向)里收 Set-Cookie。
    private func absorbSetCookies(fromRawHeaders raw: String) {
        var lines: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("set-cookie:") {
                lines.append(String(trimmed.dropFirst("set-cookie:".count)))
            }
        }
        guard !lines.isEmpty else { return }
        var captured: [String] = []
        cookieLock.lock()
        defer { cookieLock.unlock() }
        for line in lines {
            let pair = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? line
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let isDeletion = line.contains("Max-Age=0") || line.contains("max-age=0")
            if isDeletion {
                storedCookies.removeValue(forKey: name)
                captured.append("\(name)≠(删除)")
            } else {
                storedCookies[name] = value
                captured.append(name)
            }
        }
        if !captured.isEmpty {
            NCLog.log("  收到 Set-Cookie: \(captured.joined(separator: ", "))")
        }
    }

    // MARK: - HTTP

    private func post(url: URL, form: [String: String], headers: [String: String], isLogin: Bool = false) async throws -> [String: Any] {
        var composed = headers
        composed["Content-Type"] = "application/x-www-form-urlencoded"
        composed["Cookie"] = cookieHeader(isLogin: isLogin)
        // 与 Node URLSearchParams 一致的编码: 仅保留未保留字符, '+' 必须转义为 %2B,
        // 否则 base64 参数在服务器端被表单解码成空格导致解密失败(空响应)。
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        let body = form
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .sorted()
            .joined(separator: "&")

        let (data, rawHeaders, statusCode) = try await curlExecute(url: url, method: "POST",
                                                                   headers: composed, body: body)
        if ProcessInfo.processInfo.environment["NCDEBUG"] != nil {
            print("[NCDEBUG] POST \(url) → HTTP \(statusCode)\n[NCDEBUG] body: \(String(data: data.prefix(300), encoding: .utf8) ?? "(空)")")
        }
        absorbSetCookies(fromRawHeaders: rawHeaders)
        NCLog.log("POST \(url.path) → HTTP \(statusCode) 长度=\(data.count)\(data.isEmpty ? " (空响应)" : "")")
        if cookies["MUSIC_U"] != nil {
            NCLog.log("★ 已持有 MUSIC_U 登录 Cookie")
        }
        if data.isEmpty {
            NCLog.log("  ⚠ 空响应")
        }
        var json: [String: Any] = [:]
        if !data.isEmpty, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = obj
        }
        return json
    }

    // MARK: - weapi

    public func weapiRequest(path: String,        // 形如 "/login/qrcode/unikey"
                             query: [String: String] = [:],
                             payload: [String: Any] = [:]) async throws -> [String: Any] {
        var body = payload
        body["csrf_token"] = cookies["__csrf"] ?? ""
        let (params, encSecKey) = try NCCrypto.weapi(body)

        var components = URLComponents(string: Self.domain + "/weapi" + path)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let headers = [
            "Origin": Self.domain,
            "Referer": Self.domain + "/",
            "Accept": "*/*",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
        ]
        let isLogin = path.contains("login")
        let url = components.url!
        var json = try await post(url: url,
                                  form: ["params": params, "encSecKey": encSecKey],
                                  headers: headers, isLogin: isLogin)
        if json.isEmpty, !path.contains("qrcode/client/login") {
            // 一次性温和重试(风控空响应)
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let retry = try await post(url: url,
                                       form: ["params": params, "encSecKey": encSecKey],
                                       headers: headers, isLogin: isLogin)
            if !retry.isEmpty { json = retry }
        }
        return json
    }

    // MARK: - eapi

    public func eapiRequest(path: String,         // 形如 "/api/song/enhance/player/url/v1"
                            payload: [String: Any]) async throws -> [String: Any] {
        var header: [String: Any] = [
            "os": "pc",
            "appver": "2.10.11",
            "versioncode": "140",
            "mobilename": "",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "resolution": "1920x1080",
            "__csrf": cookies["__csrf"] ?? "",
            "channel": "",
            "requestId": String(Int(Date().timeIntervalSince1970 * 1000), radix: 16) + String(Int.random(in: 0x1000...0xffff), radix: 16),
            "osver": "",
            "deviceId": deviceId,
        ]
        if let musicU = cookies["MUSIC_U"], !musicU.isEmpty { header["MUSIC_U"] = musicU }
        var body = payload
        body["header"] = header
        body["e_r"] = false

        let params = try NCCrypto.eapi(path, payload: body)
        let url = URL(string: Self.apiDomain + "/eapi" + String(path.dropFirst("/api".count)))!
        let headers = [
            "User-Agent": "NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)",
        ]
        return try await post(url: url, form: ["params": params], headers: headers)
    }

    // MARK: - 业务接口

    /// 创建扫码登录 key。
    public func createLoginQRKey() async throws -> String {
        let json = try await weapiRequest(path: "/login/qrcode/unikey", payload: ["type": 3])
        if let unikey = (json["data"] as? [String: Any])?["unikey"] as? String { return unikey }
        if let unikey = json["unikey"] as? String { return unikey }
        throw NSError(domain: "NCClient", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "创建二维码失败: \(json)"])
    }

    public var loginQRURL: String { Self.domain + "/login?codekey=" }

    /// 轮询扫码状态: 800 过期 / 801 待扫码 / 802 已扫待确认 / 803 登录成功。
    /// 803 时登录 Cookie(MUSIC_U) 已被 absorbSetCookies 捕获进 cookies。
    public func checkLoginQR(key: String) async throws -> Int {
        let json = try await weapiRequest(path: "/login/qrcode/client/login",
                                          payload: ["key": key, "type": 3])
        if json.isEmpty { return 801 }   // 空响应 = 等待扫码
        let code = (json["code"] as? Int) ?? -1
        if code == 803 {
            NCLog.log("  803 登录成功响应已收到")
            if cookies["MUSIC_U"] == nil {
                // 有的实现 cookie 在紧随其后的再次轮询才下发
                NCLog.log("  803 未携带 Cookie, 立即复查一次…")
                _ = try? await weapiRequest(path: "/login/qrcode/client/login",
                                            payload: ["key": key, "type": 3])
            }
        }
        return code
    }

    /// 校验登录态并取回用户信息。返回 nil 表示未登录/cookie 失效。
    public func account() async throws -> NCProfile? {
        let json = try await weapiRequest(path: "/w/nuser/account/get")
        NCLog.log("  account/get 解析: profile=\(json["profile"] != nil) account=\(json["account"] != nil) code=\(json["code"] ?? "无")")
        if let profile = json["profile"] as? [String: Any] {
            let parsed = NCProfile(json: profile)
            NCLog.log("  NCProfile 解析: \(parsed != nil ? "成功" : "失败(缺 userId?)")")
            return parsed
        }
        return nil
    }

    public func userPlaylists(uid: Int) async throws -> [NCPlaylist] {
        let json = try await weapiRequest(path: "/user/playlist",
                                          payload: ["uid": uid, "limit": 100, "offset": 0,
                                                    "includeVideo": true])
        guard let list = json["playlist"] as? [[String: Any]] else { return [] }
        return list.compactMap { NCPlaylist(json: $0) }
    }

    public func playlistTracks(playlistId: Int) async throws -> [NCTrack] {
        let json = try await weapiRequest(path: "/v6/playlist/detail",
                                          payload: ["id": playlistId, "n": 100000, "s": 8])
        guard let playlist = json["playlist"] as? [String: Any],
              let tracks = playlist["tracks"] as? [[String: Any]] else {
            return []
        }
        return tracks.compactMap { NCTrack(json: $0) }
    }

    /// 网易云搜索(歌曲)。
    public func search(keyword: String, limit: Int = 30) async throws -> [NCTrack] {
        let json = try await weapiRequest(path: "/cloudsearch/get/web",
                                          payload: ["s": keyword, "type": 1,
                                                    "limit": limit, "offset": 0])
        guard let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else { return [] }
        return songs.compactMap { NCTrack(json: $0) }
    }

    /// 歌词: (原文 lrc, 翻译 tlyric)。
    public func lyrics(id: Int) async throws -> (lrc: String, tlyric: String?)? {
        let json = try await weapiRequest(path: "/song/lyric",
                                          payload: ["id": id, "lv": 1, "tv": 1, "rv": -1])
        guard let lrcObj = json["lrc"] as? [String: Any],
              let lrc = lrcObj["lyric"] as? String, !lrc.isEmpty else { return nil }
        let tlyric = (json["tlyric"] as? [String: Any])?["lyric"] as? String
        return (lrc, tlyric)
    }

    /// 歌曲详情(标题/歌手/封面)。
    public func songDetail(id: Int) async throws -> [NCTrack]? {
        let c = "[{\"id\":\(id)}]"
        let json = try await weapiRequest(path: "/v3/song/detail",
                                          payload: ["c": c, "ids": "[\(id)]"])
        guard let songs = json["songs"] as? [[String: Any]] else { return nil }
        return songs.compactMap { NCTrack(json: $0) }
    }

    public func songURL(id: Int, level: NCLevel) async throws -> NCSongURL? {
        let ids = "[\(id)]"   // 与官方客户端一致的字符串形式
        let json = try await eapiRequest(path: "/api/song/enhance/player/url/v1",
                                         payload: ["ids": ids,
                                                   "level": level.rawValue,
                                                   "encodeType": "flac"])
        guard let data = json["data"] as? [[String: Any]], let first = data.first else { return nil }
        return NCSongURL(json: first)
    }

    /// 兼容旧 weapi 取链(interface3 不通时的后备)。
    public func songURLFallback(id: Int, level: NCLevel) async throws -> NCSongURL? {
        let ids = "[\(id)]"
        let json = try await weapiRequest(path: "/song/enhance/player/url/v1",
                                          query: ["csrf_token": cookies["__csrf"] ?? ""],
                                          payload: ["ids": ids,
                                                    "level": level.rawValue,
                                                    "encodeType": "flac"])
        guard let data = json["data"] as? [[String: Any]], let first = data.first else { return nil }
        return NCSongURL(json: first)
    }
}
