#if DEBUG
import AppKit
import SwiftUI
import PureListenCore

// MARK: - 预览数据

/// 截图用的假数据: 覆盖真实界面会出现的各种状态, 但不触碰网络、音频与磁盘缓存。
@MainActor
enum UIPreviewData {

    static func makeState() -> AppState {
        let suite = "com.purelisten.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults, previewMode: true)
        defaults.removePersistentDomain(forName: suite)

        state.profile = NCProfile.preview(userId: 10086, nickname: "Halo", avatarURL:
            "preview://avatar/1")
        state.loginPhase = .loggedIn
        state.playlists = previewPlaylists()
        state.tracks = previewTracks()
        state.currentPlaylist = state.playlists.first
        state.previewPlaybackQueue(state.tracks, playlist: state.currentPlaylist, index: 0)

        state.playerState = .playing
        var status = ExclusivePlayer.TrackStatus()
        status.title = "夏夜の幻灯"
        status.artist = "坂本龍一 / 青葉市子"
        status.fileRate = 44100
        status.fileBits = 16
        status.deviceRate = 44100
        status.resampled = false
        status.format = "flac"
        status.level = "lossless"
        status.sizeBytes = 28462173
        status.bitrate = 896000
        status.sourceHost = "audio.example.com"
        status.sourceDetail = "Async"
        status.exclusive = true
        status.seconds = 254
        status.positionSeconds = 87
        state.trackStatus = status

        state.level = .lossless
        state.volume = 0.78
        state.autoResume = true
        state.autoDevice = true
        state.devices = previewDevices()
        state.selectedDevice = state.devices.first
        state.mediaControlKeysEnabled = true
        state.systemVolumeMirror = false
        state.blockOtherOutputs = false
        state.muteSystemWhileRunning = true
        state.lyrics = previewLyrics()
        state.lyricIndex = 7

        state.biliPhase = .loggedIn
        state.biliUname = "Halo0sama"
        state.biliAvatarURL = "preview://avatar/2"
        state.favFolders = previewFavFolders()
        state.favVideos = previewFavVideos()

        state.searchKeyword = "坂本龍一"
        state.searchResults = Array(previewTracks().prefix(8))

        state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
        state.previewSetBiliQR("https://passport.bilibili.com/h5-app/passport/login/scan?navhide=1&qrcode_key=preview-bili")
        state.biliPhase = .loggedIn
        state.loginPhase = .loggedIn
        return state
    }

    static func previewPlaylists() -> [NCPlaylist] {
        let names = ["深夜书房", "昭和歌谣", "雨的声音", "City Pop 黄金年代",
                     "需要一点钢琴", "Lo-Fi 工作流", "巴赫平均律", "坂本龍一精选",
                     "海边的 Ambient", "爵士小酒馆", "独立民谣", "古典 · 晨间"]
        return names.enumerated().map { index, name in
            NCPlaylist(id: 1000 + index, name: name,
                       coverUrl: "preview://cover/\(index)",
                       trackCount: [42, 18, 76, 31, 24, 51, 12, 38, 60, 27, 19, 44][index],
                       playCount: Int64(1200 + index * 977))
        }
    }

    static func previewTracks() -> [NCTrack] {
        let data: [(String, String, Int, Bool)] = [
            ("夏夜の幻灯", "坂本龍一 / 青葉市子", 254, false),
            ("Merry Christmas Mr. Lawrence", "坂本龍一", 275, false),
            ("Aqua", "坂本龍一", 300, false),
            ("energy flow", "坂本龍一", 268, false),
            ("雨の日に聴くピアノ", "青葉市子", 221, false),
            ("Asience", "坂本龍一", 195, false),
            ("The Sheltering Sky", "坂本龍一", 322, true),
            ("Solitude", "Bill Evans", 348, false),
            ("Waltz for Debby", "Bill Evans", 371, true),
            ("Peace Piece", "Bill Evans", 402, false),
            ("Blue in Green", "Miles Davis", 337, false),
            ("Nuvole Bianche", "Ludovico Einaudi", 351, false),
            ("Experience", "Ludovico Einaudi", 315, true),
            ("Una Mattina", "Ludovico Einaudi", 318, false),
            ("夜的第七章", "周杰伦", 242, false),
            ("菊花台", "周杰伦", 269, true),
            ("月光", "德彪西", 289, false),
            ("Gymnopédie No.1", "Erik Satie", 213, false),
        ]
        return data.enumerated().map { index, item in
            NCTrack(id: 2000 + index, name: item.0, artists: item.1, album: "—",
                    durationMs: item.2 * 1000, vipOnly: item.3,
                    coverURL: "preview://cover/\(coverForTrack(index))")
        }
    }

    /// 挑一组观感好的封面构图: 正在播放的那首用唱片(5)。
    static func coverForTrack(_ index: Int) -> Int {
        let compositions = [5, 1, 3, 2, 5, 4, 0, 1, 2, 3, 4, 0, 1, 5, 2, 3, 4, 1]
        return compositions[index % compositions.count]
    }

    static func previewDevices() -> [AudioDeviceInfo] {
        [
            AudioDeviceInfo(id: 42, uid: "BuiltInHeadphoneOutputDevice", name: "外置耳机",
                            isBuiltIn: true, currentRate: 44100, hasOutput: true),
            AudioDeviceInfo(id: 45, uid: "AppleUSBAudioEngine", name: "USB DAC · KA17",
                            isBuiltIn: false, currentRate: 96000, hasOutput: true),
            AudioDeviceInfo(id: 48, uid: "BuiltInSpeakerDevice", name: "MacBook 扬声器",
                            isBuiltIn: true, currentRate: 48000, hasOutput: true),
        ]
    }

    static func previewLyrics() -> [AppState.LyricLine] {
        let lines: [(String, String)] = [
            ("夜がゆっくりと降りてくる", "夜色缓缓降临"),
            ("窓の外は雨の音", "窗外是雨的声音"),
            ("僕らはただ静かに", "我们只是安静地"),
            ("この歌を聴いていた", "听着这首歌"),
            ("灯りを消した部屋で", "在熄了灯的房间里"),
            ("時計の針だけが鳴る", "只有钟的指针在响"),
            ("君の呼吸が近い", "你的呼吸很近"),
            ("世界がゆっくりと回る", "世界缓缓旋转"),
            ("あの夏の幻灯が", "那年夏天的幻灯"),
            ("まだ胸に映っている", "仍映在胸口"),
            ("何も言わなくていい", "什么都不必说了"),
            ("このまま朝まで", "就这样到天亮"),
        ]
        return lines.enumerated().map { index, line in
            AppState.LyricLine(id: index, time: Double(index) * 8.5,
                               text: line.0, translation: line.1)
        }
    }

    static func previewFavFolders() -> [BiliClient.FavFolder] {
        [
            BiliClient.FavFolder(id: 1, title: "默认收藏夹", mediaCount: 128),
            BiliClient.FavFolder(id: 2, title: "Hi-Fi 与声学", mediaCount: 34),
            BiliClient.FavFolder(id: 3, title: "现场 Live", mediaCount: 61),
        ]
    }

    static func previewFavVideos() -> [BiliClient.FavVideo] {
        let titles = [
            "【Hi-Res】坂本龍一 - Merry Christmas Mr. Lawrence / 现场版",
            "为什么麦克风比音箱更重要? 一次关于房间声学的实验",
            "【无损】City Pop 精选 30 首 · 车载循环",
            "从零开始搭建一台 3.5mm 直出无损播放器",
            "【Live】青葉市子 - 夜明けの歌 / 东京现场",
            "拆解: 一台 1997 年的便携 CD 机的模拟电路",
        ]
        return titles.enumerated().map { index, title in
            BiliClient.FavVideo(id: 500 + index, bvid: "BV1xx411c7mD",
                                title: title, cover: "preview://cover/\(index + 3)",
                                upper: "Halo 的声学笔记", durationSeconds: 240 + index * 97)
        }
    }
}

private extension NCProfile {
    static func preview(userId: Int, nickname: String, avatarURL: String) -> NCProfile {
        NCProfile(json: ["userId": userId, "nickname": nickname, "avatarUrl": avatarURL])
            ?? NCProfile(json: ["userId": 0, "nickname": nickname])!
    }
}

// MARK: - 程序化封面

/// 生成确定性的抽象封面图, 供截图使用(无版权顾虑, 也让整套截图风格统一)。
@MainActor
enum PreviewArtwork {

    static func activate() {
        CoverArtworkProvider.provider = { url, size in
            guard url.hasPrefix("preview://") else { return nil }
            return image(for: url, size: size)
        }
    }

    private static var cache: [String: NSImage] = [:]

    static func image(for url: String, size: CGFloat) -> NSImage? {
        let key = "\(url)@\(Int(size))"
        if let hit = cache[key] { return hit }
        guard let image = render(seed: url, size: max(size, 24)) else { return nil }
        cache[key] = image
        return image
    }

    static func render(seed: String, size: CGFloat) -> NSImage? {
        let px = Int(size.rounded())
        guard px > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let hash = stableHash(seed)
        var rng = SplitMix64(seed: hash)
        let hue = Double(hash % 360) / 360
        let hueB = (hue + 0.06 + Double(rng.next() % 90) / 500).truncatingRemainder(dividingBy: 1)
        let hueC = (hue + 0.46 + Double(rng.next() % 60) / 400).truncatingRemainder(dividingBy: 1)
        // `preview://cover/N` 的 N 直接决定构图(0 光晕 / 1 斜切 / 2 同心 / 3 色带 /
        // 4 球体 / 5 唱片), 方便给不同界面挑合适的封面。
        let suffix = Int(seed.split(separator: "/").last ?? "") ?? Int(hash >> 8) % 6
        let composition = abs(suffix) % 6

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let ctx = graphics.cgContext
        let rect = CGRect(x: 0, y: 0, width: px, height: px)

        func color(_ h: Double, _ s: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(hue: h, saturation: s, brightness: b, alpha: a)
        }

        // 基础色场
        ctx.setFillColor(color(hue, 0.5, 0.18).cgColor)
        ctx.fill(rect)
        NSGradient(colors: [color(hue, 0.72, 0.62), color(hueB, 0.80, 0.40),
                            color(hueC, 0.55, 0.16)])?
            .draw(in: rect, angle: -45 + CGFloat(rng.next() % 90))

        switch composition {
        case 0: // 光晕 + 细环
            NSGradient(colors: [color(hueB, 0.30, 1.0, 0.75), color(hueB, 0.5, 0.6, 0)])?
                .draw(in: NSBezierPath(ovalIn: CGRect(x: -CGFloat(px) * 0.2,
                                                      y: CGFloat(px) * 0.30,
                                                      width: CGFloat(px) * 1.05,
                                                      height: CGFloat(px) * 1.05)),
                       relativeCenterPosition: .zero)
            ctx.setLineWidth(CGFloat(px) * 0.003)
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.18).cgColor)
            for ring in 1...9 {
                let r = CGFloat(px) * 0.06 * CGFloat(ring)
                ctx.strokeEllipse(in: CGRect(x: CGFloat(px) * 0.68 - r, y: CGFloat(px) * 0.78 - r,
                                             width: r * 2, height: r * 2))
            }
        case 1: // 斜切色块
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(px) * 0.5, y: CGFloat(px) * 0.5)
            ctx.rotate(by: -0.42)
            ctx.setFillColor(color(hueC, 0.85, 0.72, 0.88).cgColor)
            ctx.fill(CGRect(x: -CGFloat(px) * 0.9, y: -CGFloat(px) * 0.30,
                            width: CGFloat(px) * 1.8, height: CGFloat(px) * 0.30))
            ctx.setFillColor(color(hueB, 0.6, 0.98, 0.55).cgColor)
            ctx.fill(CGRect(x: -CGFloat(px) * 0.9, y: CGFloat(px) * 0.02,
                            width: CGFloat(px) * 1.8, height: CGFloat(px) * 0.10))
            ctx.restoreGState()
        case 2: // 同心圆
            let center = CGPoint(x: CGFloat(px) * 0.5, y: CGFloat(px) * 0.5)
            for index in stride(from: 5, through: 1, by: -1) {
                let radius = CGFloat(px) * 0.09 * CGFloat(index)
                let alpha = 0.16 + 0.08 * Double(6 - index)
                ctx.setFillColor(color(index % 2 == 0 ? hueB : hueC, 0.65,
                                       0.9 - CGFloat(index) * 0.09, alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
            }
        case 3: // 横向色带
            for index in 0..<7 {
                let top = CGFloat(px) * CGFloat(index) / 7
                ctx.setFillColor(color(index % 2 == 0 ? hue : hueB, 0.55,
                                       0.95 - CGFloat(index) * 0.09,
                                       0.20 + 0.06 * CGFloat(index % 3)).cgColor)
                ctx.fill(CGRect(x: 0, y: top, width: CGFloat(px), height: CGFloat(px) / 9))
            }
        case 4: // 球体 + 一道细线: 极简海报
            let center = CGPoint(x: CGFloat(px) * 0.44, y: CGFloat(px) * 0.56)
            let radius = CGFloat(px) * 0.34
            NSGradient(colors: [color(hueB, 0.22, 1.0, 0.98),
                                color(hueB, 0.62, 0.62, 0.95),
                                color(hueC, 0.80, 0.18, 0.95)])?
                .draw(in: NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                      width: radius * 2, height: radius * 2)),
                       relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
            ctx.setLineWidth(max(1, CGFloat(px) * 0.005))
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.50).cgColor)
            ctx.move(to: CGPoint(x: 0, y: CGFloat(px) * 0.26))
            ctx.addLine(to: CGPoint(x: CGFloat(px), y: CGFloat(px) * 0.26))
            ctx.strokePath()
            ctx.setFillColor(color(hueC, 0.7, 0.95, 0.9).cgColor)
            let dot = CGFloat(px) * 0.035
            ctx.fillEllipse(in: CGRect(x: CGFloat(px) * 0.82 - dot,
                                       y: CGFloat(px) * 0.26 - dot,
                                       width: dot * 2, height: dot * 2))
        default: // 唱片
            let center = CGPoint(x: CGFloat(px) * 0.5, y: CGFloat(px) * 0.5)
            let radius = CGFloat(px) * 0.42
            ctx.setFillColor(NSColor(white: 0.06, alpha: 0.92).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
            ctx.setLineWidth(max(0.6, CGFloat(px) * 0.0015))
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
            for groove in 1...14 {
                let r = radius * (0.34 + CGFloat(groove) * 0.046)
                ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                             width: r * 2, height: r * 2))
            }
            let labelRadius = radius * 0.30
            ctx.setFillColor(color(hueB, 0.68, 0.86, 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - labelRadius, y: center.y - labelRadius,
                                       width: labelRadius * 2, height: labelRadius * 2))
            ctx.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor)
            let hole = max(1.2, CGFloat(px) * 0.012)
            ctx.fillEllipse(in: CGRect(x: center.x - hole, y: center.y - hole,
                                       width: hole * 2, height: hole * 2))
        }

        // 斜向高光
        if let shine = NSGradient(colors: [NSColor(white: 1, alpha: 0.20),
                                           NSColor(white: 1, alpha: 0.0)]) {
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.rotate(by: .pi / 8)
            shine.draw(in: CGRect(x: -CGFloat(px), y: CGFloat(px) * 0.34,
                                  width: CGFloat(px) * 3, height: CGFloat(px) * 0.13), angle: 0)
            ctx.restoreGState()
        }

        // 胶片颗粒
        drawGrain(in: ctx, rect: rect, amount: 0.04, rng: &rng)

        // 暗角
        if let vignette = NSGradient(colors: [NSColor(white: 0, alpha: 0.0),
                                              NSColor(white: 0, alpha: 0.34)]) {
            vignette.draw(in: NSBezierPath(ovalIn: rect.insetBy(dx: -CGFloat(px) * 0.10,
                                                                dy: -CGFloat(px) * 0.10)),
                          relativeCenterPosition: .zero)
        }

        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: px, height: px))
        image.addRepresentation(rep)
        return image
    }

    /// 细颗粒: 让纯色渐变有"印刷品"的质感。
    private static func drawGrain(in ctx: CGContext, rect: CGRect, amount: Double,
                                  rng: inout SplitMix64) {
        let side = 64
        var bytes = [UInt8](repeating: 0, count: side * side)
        for index in 0..<bytes.count {
            bytes[index] = UInt8(rng.next() % 255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let noise = CGImage(width: side, height: side, bitsPerComponent: 8,
                                  bitsPerPixel: 8, bytesPerRow: side,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.overlay)
        ctx.setAlpha(CGFloat(amount))
        ctx.draw(noise, in: rect)
        ctx.restoreGState()
    }

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
#endif
