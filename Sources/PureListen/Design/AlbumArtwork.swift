import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - 封面缓存

/// 封面内存缓存。主线程隔离, 因为 NSImage / NSCache 的绘制与解码都在主线程完成。
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 800
    }

    func cached(for url: String, size: Int) -> NSImage? {
        cache.object(forKey: key(url, size) as NSString)
    }

    func image(for url: String, size: Int) async -> NSImage? {
        guard !url.isEmpty else { return nil }
        let k = key(url, size)
        if let hit = cache.object(forKey: k as NSString) { return hit }
        if let task = inFlight[k] { return await task.value }

        let task = Task<NSImage?, Never> { [url, size] in
            if let artwork = CoverArtworkProvider.provider?(url, CGFloat(size)) {
                return artwork
            }
            return await Self.download(url: url, size: size)
        }
        inFlight[k] = task
        let image = await task.value
        inFlight[k] = nil
        if let image { cache.setObject(image, forKey: k as NSString) }
        return image
    }

    private func key(_ url: String, _ size: Int) -> String {
        "\(url)#\(size)"
    }

    private static func download(url: String, size: Int) async -> NSImage? {
        guard var comps = URLComponents(string: url) else { return nil }
        // 网易云图床支持 param 缩略; 其他源忽略亦可。
        if comps.host?.contains("126.net") == true {
            comps.queryItems = [URLQueryItem(name: "param", value: "\(size)y\(size)")]
        }
        guard let source = comps.url else { return nil }
        var request = URLRequest(url: source)
        request.timeoutInterval = 12
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = NSImage(data: data) else { return nil }
        return image
    }
}

// MARK: - 封面视图

/// 统一封面组件: 圆角、悬停高光、占位符、可选投影。
struct CoverArtwork: View {
    let url: String
    var size: CGFloat
    var radius: CGFloat? = nil
    var shadow: Bool = false
    var borderOpacity: Double = 0.10

    @State private var image: NSImage?
    /// 当前已加载的 (url, size)，用于在 URL 变化时丢弃旧图，避免串封面。
    @State private var loadedKey: String = ""

    private var loadKey: String { "\(url)|\(Int(size))" }

    var body: some View {
        let corner = radius ?? max(DS.Radius.artSmall, size * 0.14)
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(DS.Palette.surfaceSelected)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: max(10, size * 0.28), weight: .medium))
                    .foregroundStyle(DS.Palette.textQuaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.8)
        }
        .shadow(color: shadow ? .black.opacity(0.35) : .clear,
                radius: shadow ? max(8, size * 0.08) : 0,
                y: shadow ? max(4, size * 0.045) : 0)
        .task(id: loadKey) {
            let key = loadKey
            guard loadedKey != key else { return }
            loadedKey = key

            let pixelSize = Int(size * 2)
            // 命中缓存时直接切换，避免闪一下占位符。
            if let cached = ArtworkCache.shared.cached(for: url, size: pixelSize) {
                image = cached
                return
            }
            // 旧图立即清掉：宁可短暂显示占位符，也不能显示上一个歌单/上一首歌的封面。
            image = nil
            guard !url.isEmpty else { return }
            let loaded = await ArtworkCache.shared.image(for: url, size: pixelSize)
            guard !Task.isCancelled, loadedKey == key else { return }
            image = loaded
        }
    }
}

// MARK: - 封面取色

/// 从封面里取出的「音乐色」。
///
/// 规则: 只有一种色相参与全局着色, 并把它压到能当文字/控件用的亮度区间;
/// 纯灰封面回退到系统强调色, 避免界面变成一团泥。
struct AlbumPalette: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var isChromatic: Bool

    static let neutral = AlbumPalette(hue: 0.58, saturation: 0.0, brightness: 0.5, isChromatic: false)

    /// 界面主色(深色模式偏亮, 浅色模式偏深)。
    var tint: Color {
        let s = isChromatic ? min(max(saturation * 0.92, 0.42), 0.78) : 0.0
        let b = isChromatic ? min(max(brightness * 1.02, 0.66), 0.90) : 0.0
        return Color(nsColor: NSColor(hue: hue, saturation: s, brightness: b, alpha: 1))
    }

    var tintLight: Color {
        let s = isChromatic ? min(max(saturation * 0.95, 0.5), 0.85) : 0.0
        let b = isChromatic ? min(max(brightness * 0.62, 0.34), 0.55) : 0.0
        return Color(nsColor: NSColor(hue: hue, saturation: s, brightness: b, alpha: 1))
    }

    /// 深色画布上的大面积晕染。
    var glow: Color {
        Color(nsColor: NSColor(hue: hue, saturation: isChromatic ? 0.85 : 0.0,
                               brightness: isChromatic ? 0.55 : 0.35, alpha: 1))
    }

    /// 与黑白混合后的柔和色, 用于背景 wash。
    func wash(dark: Bool) -> Color {
        Color(nsColor: NSColor(hue: hue,
                               saturation: isChromatic ? 0.55 : 0.0,
                               brightness: dark ? 0.30 : 0.86,
                               alpha: 1))
    }

    static func == (lhs: AlbumPalette, rhs: AlbumPalette) -> Bool {
        lhs.hue == rhs.hue && lhs.saturation == rhs.saturation
            && lhs.brightness == rhs.brightness && lhs.isChromatic == rhs.isChromatic
    }
}

/// 取色缓存。
@MainActor
final class AlbumPaletteStore {
    static let shared = AlbumPaletteStore()
    private var cache: [String: AlbumPalette] = [:]
    private var tasks: [String: Task<AlbumPalette, Never>] = [:]

    func cached(for url: String) -> AlbumPalette? { cache[url] }

    func palette(for url: String) async -> AlbumPalette {
        if let hit = cache[url] { return hit }
        if let task = tasks[url] { return await task.value }
        let task = Task<AlbumPalette, Never> { [url] in
            guard let image = await ArtworkCache.shared.image(for: url, size: 60) else {
                return .neutral
            }
            return Self.extract(from: image) ?? .neutral
        }
        tasks[url] = task
        let palette = await task.value
        tasks[url] = nil
        cache[url] = palette
        return palette
    }

    /// 缩到 24×24 取"最有色彩"的一撮像素的加权平均。
    private static func extract(from image: NSImage) -> AlbumPalette? {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        var weightedHue = 0.0
        var weightedSat = 0.0
        var weightedBri = 0.0
        var totalWeight = 0.0
        var bestChroma = -1.0
        var bestColor = NSColor(white: 0.5, alpha: 1)

        for index in 0..<(side * side) {
            let offset = index * 4
            let r = Double(data[offset]) / 255
            let g = Double(data[offset + 1]) / 255
            let b = Double(data[offset + 2]) / 255
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1).srgb
            var h: CGFloat = 0, s: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &bri, alpha: &a)
            guard bri > 0.08, bri < 0.98 else { continue }
            let chroma = Double(s) * (0.55 + 0.45 * Double(bri))
            if chroma > bestChroma {
                bestChroma = chroma
                bestColor = color
            }
            // 只统计有色像素, 黑色/白色区域不参与色相平均。
            guard s > 0.18 else { continue }
            let weight = Double(s) * Double(bri) * Double(s)
            weightedHue += Double(h) * weight
            weightedSat += Double(s) * weight
            weightedBri += Double(bri) * weight
            totalWeight += weight
        }

        guard totalWeight > 0.0001 else {
            // 彩色像素太少 → 取最亮像素做中性色。
            var best: CGFloat = -1
            for index in 0..<(side * side) {
                let offset = index * 4
                let bri = (Double(data[offset]) + Double(data[offset + 1]) + Double(data[offset + 2])) / 3 / 255
                if bri > best { best = bri }
            }
            return AlbumPalette(hue: 0.58, saturation: 0, brightness: 0.5, isChromatic: false)
        }

        // 色相是环形量: 用向量平均避免 350° 与 10° 被平均成 180°。
        var x = 0.0, y = 0.0
        for index in 0..<(side * side) {
            let offset = index * 4
            let color = NSColor(srgbRed: Double(data[offset]) / 255,
                                green: Double(data[offset + 1]) / 255,
                                blue: Double(data[offset + 2]) / 255,
                                alpha: 1).srgb
            var h: CGFloat = 0, s: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &bri, alpha: &a)
            guard s > 0.18, bri > 0.08 else { continue }
            let weight = Double(s) * Double(bri)
            x += cos(Double(h) * 2 * .pi) * weight
            y += sin(Double(h) * 2 * .pi) * weight
        }
        var hue = atan2(y, x) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let saturation = weightedSat / totalWeight
        let brightness = weightedBri / totalWeight

        var bestH: CGFloat = 0, bestS: CGFloat = 0, bestB: CGFloat = 0, bestA: CGFloat = 0
        bestColor.getHue(&bestH, saturation: &bestS, brightness: &bestB, alpha: &bestA)

        // 以最有色彩像素的色相为主(比平均色相更有辨识度), 但平均差异过大时也用平均。
        let primary = Double(bestH)
        var delta = abs(primary - hue)
        if delta > 0.5 { delta = 1 - delta }
        let finalHue = delta < 0.22 ? primary : hue

        return AlbumPalette(hue: finalHue,
                            saturation: Double(max(bestS, CGFloat(saturation))),
                            brightness: Double(max(bestB, CGFloat(brightness))),
                            isChromatic: bestChroma > 0.12)
    }
}

// MARK: - 背景晕染

/// 把封面色铺成柔和的环境光, 是整套界面的"氛围层"。
///
/// 克制原则: 只在顶部形成一束光, 向下迅速退到画布底色; 浅色模式几乎只剩一层暖光。
struct AlbumWash: View {
    var palette: AlbumPalette
    var intensity: Double = 1
    @Environment(\.dsIsDark) private var isDark

    private var glow: Color {
        Color(nsColor: NSColor(hue: palette.hue,
                               saturation: palette.isChromatic ? (isDark ? 0.66 : 0.50) : 0,
                               brightness: isDark ? 0.52 : 0.97,
                               alpha: 1))
    }

    var body: some View {
        ZStack {
            DS.Palette.canvas
            if palette.isChromatic {
                RadialGradient(
                    colors: [
                        glow.opacity((isDark ? 0.32 : 0.06) * intensity),
                        glow.opacity((isDark ? 0.09 : 0.02) * intensity),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.5, y: -0.12),
                    startRadius: 0,
                    endRadius: isDark ? 320 : 220
                )
                LinearGradient(
                    colors: [.clear,
                             glow.opacity((isDark ? 0.05 : 0.01) * intensity),
                             .clear],
                    startPoint: .top, endPoint: .bottom
                )
                // 底部再压一层暗色, 让浮动玻璃有东西可以"虚化"(浅色模式保持中性纸白)。
                LinearGradient(colors: [.clear, .black.opacity(isDark ? 0.22 : 0.0)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
    }
}

// MARK: - 音乐色注入

/// 读取封面 → 取色 → 把「音乐色」注入环境, 并提供氛围背景。
///
/// 所有界面都以它包一层, 于是整屏的强调色都来自当前播放的封面。
struct AlbumTintProvider<Content: View>: View {
    var url: String
    var intensity: Double = 1
    var showsWash: Bool = true
    @ViewBuilder var content: () -> Content

    @State private var palette: AlbumPalette = .neutral
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dsIsDark) private var isDark
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tint: Color {
        scheme == .dark ? palette.tint : palette.tintLight
    }

    var body: some View {
        ZStack {
            if showsWash {
                AlbumWash(palette: palette, intensity: intensity)
                    .ignoresSafeArea()
            }
            content()
                .environment(\.albumTint, tint)
                .environment(\.dsIsDark, scheme == .dark)
        }
        .task(id: url) {
            let loaded = await AlbumPaletteStore.shared.palette(for: url)
            withAnimation(.easeOut(duration: 0.5)) { palette = loaded }
        }
    }
}
