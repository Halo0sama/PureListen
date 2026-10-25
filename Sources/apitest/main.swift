import Foundation
import PureListenCore

// apitest: 网易/B站 API 自测 CLI
// 用法: apitest <qr|url|playlists|search|httapitest|biliqr> ...

let cookiePath = NSString(string: "~/.purelisten-cookies.json").expandingTildeInPath

func loadCookies() -> [String: String] {
    guard let data = FileManager.default.contents(atPath: cookiePath),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
    return dict
}
func saveCookies(_ client: NCClient) {
    let data = (try? JSONSerialization.data(withJSONObject: client.cookies)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: cookiePath))
}

let client = NCClient(cookies: loadCookies())
let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "qr"
let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        switch command {
        case "qr":
            let key = try await client.createLoginQRKey()
            print("二维码 key: \(key)")
            print("登录 URL: \(client.loginQRURL + key)")
            for _ in 0..<15 {
                let code = try await client.checkLoginQR(key: key)
                print("  code=\(code)")
                if code == 803 {
                    saveCookies(client)
                    print("✅ 登录成功, cookie 已保存")
                    if let profile = try await client.account() {
                        print("  用户: \(profile.nickname) (uid=\(profile.userId))")
                        let playlists = try await client.userPlaylists(uid: profile.userId)
                        print("  歌单数: \(playlists.count)")
                    }
                    semaphore.signal()
                    return
                }
                if code == 800 { print("  二维码已过期"); semaphore.signal(); return }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            print("⏱ 轮询结束(未扫码)")

        case "url":
            let songId = Int(args.count > 2 ? args[2] : "2034742057") ?? 2034742057
            let level = NCLevel(rawValue: args.count > 3 ? args[3] : "lossless") ?? .lossless
            print("取歌 \(songId) level=\(level.rawValue) 已登录=\(client.isLoggedIn)")
            var result = try await client.songURL(id: songId, level: level)
            if result == nil {
                result = try await client.songURLFallback(id: songId, level: level)
            }
            if let result {
                print("  url: \(result.url ?? "nil")")
                print("  格式: \(result.format) 等级: \(result.level) 码率: \(result.br)")
                if let trial = result.freeTrialInfo { print("  ⚠️ \(trial)") }
            } else {
                print("  未取到直链(无版权或需要 VIP)")
            }

        case "playlists":
            guard let profile = try await client.account() else {
                print("未登录"); semaphore.signal(); return
            }
            print("用户: \(profile.nickname)")
            let playlists = try await client.userPlaylists(uid: profile.userId)
            for p in playlists.prefix(10) { print("  [\(p.id)] \(p.name) (\(p.trackCount) 首)") }

        case "search":
            let keyword = args.count > 2 ? args[2] : "周杰伦"
            let results = try await client.search(keyword: keyword)
            print("搜索「\(keyword)」→ \(results.count) 首")
            for t in results.prefix(8) {
                print("  [\(t.id)] \(t.name) - \(t.artists) vip=\(t.vipOnly)")
            }

        case "hct":
            let resp = try await HTTPTask.get(url: "https://api.bilibili.com/x/frontend/finger/spi",
                                              headers: ["User-Agent": BiliClient.UA,
                                                        "Referer": "https://www.bilibili.com/"])
            print("HTTP \(resp.statusCode) json code=\(resp.json["code"] ?? "无")")
            print("setCookies: \(resp.setCookies.keys.sorted().joined(separator: ", "))")
            if let data = resp.json["data"] as? [String: Any] {
                print("buvid 存在: \(data["b_3"] != nil)")
            }

        case "biliqr":
            let bili = BiliClient()
            let (url, key) = try await bili.createLoginQR()
            print("B站登录 URL: \(url)")
            print("key: \(key)")
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 2_500_000_000)
                let code = try await bili.pollLoginQR(key: key)
                print("  poll code=\(code)")
                if code == 0 {
                    print("✅ B站登录成功 cookies: \(bili.cookies.keys.sorted().joined(separator: ","))")
                    if let account = try await bili.account() {
                        print("  \(account.uname) mid=\(account.mid)")
                        let folders = try await bili.favoriteFolders(mid: account.mid)
                        print("  收藏夹: \(folders.count) 个")
                        for f in folders { print("    - \(f.title) (\(f.mediaCount))") }
                    }
                    semaphore.signal(); return
                }
                if code == 86038 { print("  二维码过期"); semaphore.signal(); return }
            }

        default:
            print("未知命令: \(command)")
            print("可用: qr | url <id> <level> | playlists | search <kw> | hct | biliqr")
        }
    } catch {
        print("❌ 出错: \(error)")
    }
    semaphore.signal()
}

semaphore.wait()
