import AppKit
import SwiftUI

// MARK: - 氛围背景

/// 窗口的整幅背景: 放大的模糊封面 + 遮罩 + 音乐色光晕 + 暗角。
///
/// 它是整个窗口的"底", 所有内容都浮在它上面; 玻璃(音质胶囊)压在这一层之上,
/// 因此玻璃取到的就是封面的颜色 —— 这正是 Liquid Glass 想要的效果。
///
/// 对比度是硬指标: 深色模式下标题区域的背景亮度压到 ~0.2, 白字对比 > 4.5:1。
struct WindowAmbientBackground: View {
    var url: String

    @State private var image: NSImage?
    @Environment(\.dsIsDark) private var isDark
    @Environment(\.albumTint) private var tint

    var body: some View {
        ZStack {
            DS.Palette.canvas

            artwork
                .backgroundExtensionEffect()

            scrim
            glow
            vignette
        }
        .task(id: url) { await loadArtwork() }
        .ignoresSafeArea()
    }

    // MARK: 封面

    @ViewBuilder
    private var artwork: some View {
        GeometryReader { geo in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(1.35)
                    .blur(radius: 60)
                    .saturation(isDark ? 1.18 : 1.12)
                    .brightness(isDark ? -0.08 : 0.02)
                    .opacity(isDark ? 0.92 : 0.26)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    // 浅色模式: 氛围只留在顶部, 内容区回到中性纸白(REVIEW-1 P1-1)。
                    .mask {
                        if isDark {
                            Rectangle()
                        } else {
                            LinearGradient(stops: [
                                .init(color: .white, location: 0.00),
                                .init(color: .white.opacity(0.92), location: 0.38),
                                .init(color: .white.opacity(0.45), location: 0.60),
                                .init(color: .clear, location: 0.80),
                            ], startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .animation(.easeOut(duration: 0.55), value: url)
            } else {
                // 没有封面: 保持中性, 不制造灰色雾团。
                Color.clear
            }
        }
    }

    // MARK: 遮罩

    @ViewBuilder
    private var scrim: some View {
        if isDark {
            ZStack(alignment: .leading) {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.36), location: 0.00),
                    .init(color: .black.opacity(0.30), location: 0.30),
                    .init(color: .black.opacity(0.40), location: 0.72),
                    .init(color: .black.opacity(0.62), location: 1.00),
                ], startPoint: .top, endPoint: .bottom)

                // 内容列下方的径向压暗: 封面/标题落在更深的底上。
                RadialGradient(colors: [.black.opacity(0.20), .black.opacity(0.06), .clear],
                               center: UnitPoint(x: 0.62, y: 0.42),
                               startRadius: 80, endRadius: 620)

                // 侧边栏一侧压暗, 导航文字才立得住。
                LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.16), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: DS.Size.sidebarWidth + 80)
            }
        } else {
            ZStack(alignment: .leading) {
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.48), location: 0.00),
                    .init(color: .white.opacity(0.38), location: 0.30),
                    .init(color: .white.opacity(0.32), location: 0.72),
                    .init(color: .white.opacity(0.26), location: 1.00),
                ], startPoint: .top, endPoint: .bottom)

                LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.12), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: DS.Size.sidebarWidth + 80)
            }
        }
    }

    // MARK: 光

    /// 顶部一束音乐色的光。全局唯一的彩色光源。
    @ViewBuilder
    private var glow: some View {
        if image != nil {
            RadialGradient(colors: [
                tint.opacity(isDark ? 0.16 : 0.14),
                tint.opacity(isDark ? 0.05 : 0.05),
                .clear,
            ], center: UnitPoint(x: 0.46, y: 0.02), startRadius: 10, endRadius: 560)
                .blendMode(isDark ? .plusLighter : .normal)
        } else {
            LinearGradient(colors: [Color.white.opacity(isDark ? 0.05 : 0.30), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42))
        }
    }

    private var vignette: some View {
        RadialGradient(colors: [.clear, .black.opacity(isDark ? 0.40 : 0.06)],
                       center: .center, startRadius: 220, endRadius: 720)
    }

    // MARK: 加载

    private func loadArtwork() async {
        guard !url.isEmpty else {
            withAnimation(.easeOut(duration: 0.4)) { image = nil }
            return
        }
        let loaded = await ArtworkCache.shared.image(for: url, size: 900)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.55)) { image = loaded }
    }
}
