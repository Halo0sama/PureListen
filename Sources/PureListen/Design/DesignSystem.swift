import AppKit
import SwiftUI

// MARK: - 设计系统
//
// 净听 · macOS 27 "Golden Gate" 视觉语言。
//
// 三条硬规则:
// 1. 玻璃只用于"浮在内容之上"的层(播放控制、标签切换、浮动面板), 列表与卡片一律用实体表面,
//    这样界面在 Reduce Transparency 下依然成立, 也不会糊成一片。
// 2. 全局只有一束彩色光: 由当前封面取样的「音乐色」。除了它和系统强调色, 其余全是黑白灰。
// 3. 圆角同心递进: 外层大、内层小, 每次嵌套减去内边距, 视觉上才是"一块玻璃被雕出来"。

enum DS {

    // MARK: 间距(4pt 网格)

    enum Space {
        static let hairline: CGFloat = 1
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
        static let popoverPadding: CGFloat = 16
        static let windowPadding: CGFloat = 28
    }

    // MARK: 圆角(同心)

    enum Radius {
        /// 窗口圆角: macOS 27 系统统一 16pt(实测), 内容层与之同心。
        static let window: CGFloat = 16
        /// 大面板 / 播放器底板。
        static let panel: CGFloat = 16
        /// 卡片。
        static let card: CGFloat = 12
        /// 列表行 / 内嵌分组。
        static let row: CGFloat = 10
        /// 输入框 / 小控件。
        static let control: CGFloat = 8
        /// 徽标。
        static let chip: CGFloat = 6
        /// 封面(小)。
        static let artSmall: CGFloat = 8
        /// 封面(中)。
        static let art: CGFloat = 12
        /// 封面(大 / 英雄区)。
        static let artHero: CGFloat = 18

        /// 同心内圆角: 外层半径减去内边距。
        static func inner(_ outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat {
            max(outer - inset, minimum)
        }
    }

    // MARK: 字体

    enum TypeScale {
        /// 英雄区大标题(窗口)。
        static let heroTitle = Font.system(size: 26, weight: .semibold)
        /// 分区标题。
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        /// 弹窗内页面标题。
        static let navTitle = Font.system(size: 15, weight: .semibold)
        /// 曲名(列表主行)。
        static let rowTitle = Font.system(size: 13, weight: .medium)
        /// 正文 13pt(系统 body)。
        static let body = Font.system(size: 13, weight: .regular)
        /// 次要说明。
        static let caption = Font.system(size: 11, weight: .regular)
        /// 元信息 / 数字。
        static let meta = Font.system(size: 10.5, weight: .medium)
        /// 微标签(全大写 + 字距)。
        static let micro = Font.system(size: 9, weight: .semibold)
        /// 时间码。
        static let timecode = Font.system(size: 10.5, weight: .medium).monospacedDigit()
        /// 大号时间码(窗口)。
        static let timecodeLarge = Font.system(size: 11.5, weight: .medium).monospacedDigit()
    }

    enum Tracking {
        /// 大标题收紧字距。
        static let display: CGFloat = -0.4
        /// 微标签放开字距。
        static let micro: CGFloat = 0.9
        /// 普通收紧。
        static let tight: CGFloat = -0.1
    }

    // MARK: 颜色

    enum Palette {
        // 画布: 深色是近乎墨黑的暖黑, 浅色是微暖的纸白。
        static let canvas = Color.dynamic(
            light: NSColor(srgbRed: 0.956, green: 0.949, blue: 0.933, alpha: 1),
            dark: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.066, alpha: 1)
        )
        /// 画布之上的一层(窗口内容区)。
        static let canvasElevated = Color.dynamic(
            light: NSColor(srgbRed: 0.976, green: 0.972, blue: 0.960, alpha: 1),
            dark: NSColor(srgbRed: 0.075, green: 0.075, blue: 0.088, alpha: 1)
        )
        /// 卡片表面。
        static let surface = Color.dynamic(
            light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.78),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.055)
        )
        /// 实体表面: 需要"浮在模糊背景上"时使用(窗口里的设置卡片), 不透出背景。
        static let surfaceSolid = Color.dynamic(
            light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92),
            dark: NSColor(srgbRed: 0.082, green: 0.082, blue: 0.090, alpha: 0.94)
        )
        /// 悬停表面。
        static let surfaceHover = Color.dynamic(
            light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.045),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.085)
        )
        /// 选中表面。
        static let surfaceSelected = Color.dynamic(
            light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)
        )
        /// 细描边。
        static let hairline = Color.dynamic(
            light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.075),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.075)
        )
        /// 强描边(玻璃高光边)。
        static let hairlineStrong = Color.dynamic(
            light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)
        )
        static let textPrimary = Color.dynamic(
            light: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.94)
        )
        static let textSecondary = Color.dynamic(
            light: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 0.66),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.66)
        )
        static let textTertiary = Color.dynamic(
            light: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 0.47),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.60)
        )
        static let textQuaternary = Color.dynamic(
            light: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 0.24),
            dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.42)
        )
        /// 成功 / 位完美。
        static let mint = Color.dynamic(
            light: NSColor(srgbRed: 0.10, green: 0.55, blue: 0.38, alpha: 1),
            dark: NSColor(srgbRed: 0.36, green: 0.90, blue: 0.68, alpha: 1)
        )
        static let amber = Color.dynamic(
            light: NSColor(srgbRed: 0.72, green: 0.44, blue: 0.06, alpha: 1),
            dark: NSColor(srgbRed: 1.0, green: 0.72, blue: 0.30, alpha: 1)
        )
        /// 品牌强调色: 固定靛紫, 与封面无关。
        /// 用于开关、选中态这类"需要稳定语义"的控件 —— 否则在棕色封面上开关会变成棕色。
        static let brandAccent = Color.dynamic(
            light: NSColor(srgbRed: 0.36, green: 0.28, blue: 0.88, alpha: 1),
            dark: NSColor(srgbRed: 0.60, green: 0.53, blue: 1.0, alpha: 1)
        )
        static let rose = Color.dynamic(
            light: NSColor(srgbRed: 0.78, green: 0.20, blue: 0.28, alpha: 1),
            dark: NSColor(srgbRed: 1.0, green: 0.42, blue: 0.48, alpha: 1)
        )
    }

    // MARK: 动效

    enum Motion {
        /// 悬停 / 颜色变化: 系统 interactiveSpring(约 0.15s 落定)。
        static let quick = Animation.interactiveSpring()
        /// 常规状态切换: Golden Gate 用系统 snappy 弹簧。
        static let standard = Animation.snappy(duration: 0.28)
        /// 页面 / 展开: smooth 弹簧, 比 26 时代更慢更稳。
        static let page = Animation.smooth(duration: 0.38)
        /// 按下反馈。
        static let press = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.72)
        /// 缓慢呼吸(波形 / 光晕)。
        static let breathe = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    }

    // MARK: 尺寸

    enum Size {
        static let popoverWidth: CGFloat = 372
        static let popoverHeight: CGFloat = 588
        static let windowWidth: CGFloat = 940
        static let windowHeight: CGFloat = 640
        static let sidebarWidth: CGFloat = 168
        static let toolbarHeight: CGFloat = 52
        static let rowHeight: CGFloat = 44
        static let artRow: CGFloat = 34
        static let artBar: CGFloat = 40
        static let artHero: CGFloat = 268
        static let controlHeight: CGFloat = 28
    }

    // MARK: 阴影

    enum Shadow {
        static let art = (color: Color.black.opacity(0.38), radius: CGFloat(22), y: CGFloat(12))
        static let floating = (color: Color.black.opacity(0.30), radius: CGFloat(16), y: CGFloat(6))
        static let panel = (color: Color.black.opacity(0.20), radius: CGFloat(10), y: CGFloat(3))
    }
}

// MARK: - 动态颜色 / 工具

extension Color {
    /// 用一个动态 Provider 建颜色, 随浅/深色外观自动切换。
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension NSColor {
    /// 转 sRGB, 方便做色彩运算。
    var srgb: NSColor { usingColorSpace(.sRGB) ?? self }

    /// 按 HSL 微调(保留色相)。
    func adjusted(saturationScale: CGFloat = 1, brightnessScale: CGFloat = 1,
                  saturationOverride: CGFloat? = nil, brightnessOverride: CGFloat? = nil) -> NSColor {
        let c = srgb
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h,
                       saturation: saturationOverride ?? min(max(s * saturationScale, 0), 1),
                       brightness: brightnessOverride ?? min(max(b * brightnessScale, 0), 1),
                       alpha: a)
    }
}

// MARK: - 环境

private struct AlbumTintKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

private struct IsDarkKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    /// 当前封面取样出的「音乐色」。
    var albumTint: Color {
        get { self[AlbumTintKey.self] }
        set { self[AlbumTintKey.self] = newValue }
    }

    var dsIsDark: Bool {
        get { self[IsDarkKey.self] }
        set { self[IsDarkKey.self] = newValue }
    }
}

extension View {
    /// 注入当前外观状态(浅/深色)与音乐色。
    func dsAppearance(tint: Color) -> some View {
        modifier(DSAppearanceModifier(tint: tint))
    }
}

private struct DSAppearanceModifier: ViewModifier {
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .environment(\.dsIsDark, scheme == .dark)
            .environment(\.albumTint, tint)
    }
}

// MARK: - 表面 / 玻璃 / 交互

extension View {

    /// 实体卡片表面: 用于列表分组、设置面板。
    func dsSurface(_ radius: CGFloat = DS.Radius.card,
                   fill: Color = DS.Palette.surface,
                   stroke: Bool = true) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay {
                    if stroke {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                    }
                }
        }
    }

    /// Liquid Glass 底座: 浮在内容之上的控制层。Reduce Transparency 时退化为实体表面。
    @ViewBuilder
    func dsGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false,
                           fallbackFill: Color = DS.Palette.surfaceSelected,
                           castsShadow: Bool = true) -> some View {
        modifier(DSGlassModifier(shape: shape, tint: tint, interactive: interactive,
                                 fallbackFill: fallbackFill, castsShadow: castsShadow))
    }

    /// 悬停高亮(自绘, 不动画布局, 只淡入淡出)。
    func dsHover(_ isHovering: Bool, radius: CGFloat = DS.Radius.row,
                 strength: Double = 1) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DS.Palette.surfaceHover.opacity(isHovering ? strength : 0))
        }
    }

    /// 按下缩放反馈。
    func dsPressable(scale: CGFloat = 0.94) -> some View {
        modifier(DSPressableModifier(scale: scale))
    }

    /// 极细描边。
    func dsHairline(_ radius: CGFloat, opacity: Double = 1) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DS.Palette.hairline.opacity(opacity), lineWidth: 1)
        }
    }

    /// 把内层圆角切成与外层同心的样子。
    func dsConcentric(_ outer: CGFloat, inset: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: DS.Radius.inner(outer, inset: inset),
                                   style: .continuous))
    }

    func dsShadow(_ shadow: (color: Color, radius: CGFloat, y: CGFloat)) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

private struct DSGlassModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool
    var fallbackFill: Color
    var castsShadow: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(fallbackFill.opacity(0.6)) }
                    .overlay {
                        shape.strokeBorder(DS.Palette.hairlineStrong.opacity(0.4), lineWidth: 1)
                    }
            }
        } else {
            content
                .glassEffect(glass, in: shape)
                .overlay {
                    // 顶面反光: 模拟玻璃厚度带来的柔和高光。
                    shape
                        .fill(LinearGradient(colors: [Color.white.opacity(0.10),
                                                      Color.white.opacity(0.02),
                                                      .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .allowsHitTesting(false)
                }
                .overlay {
                    // 底部内阴影: 玻璃的厚度。
                    shape
                        .fill(LinearGradient(colors: [.clear, .black.opacity(0.10)],
                                             startPoint: .center, endPoint: .bottom))
                        .allowsHitTesting(false)
                        .blendMode(.plusDarker)
                }
                .overlay {
                    // 高光边: 让边缘在深色画布上也立得住。
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.40),
                                                Color.white.opacity(0.12),
                                                Color.white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.9)
                }
                .shadow(color: castsShadow ? .black.opacity(0.45) : .clear, radius: 0.7)
                .shadow(color: castsShadow ? .black.opacity(0.32) : .clear, radius: 18, y: 8)
        }
    }

    private var glass: Glass {
        var glass = interactive ? Glass.regular.interactive() : Glass.regular
        if let tint { glass = glass.tint(tint) }
        return glass
    }
}

private struct DSPressableModifier: ViewModifier {
    var scale: CGFloat
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? scale : 1)
            .animation(DS.Motion.press, value: pressed)
            .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity,
                                pressing: { pressed = $0 }, perform: {})
    }
}

// MARK: - 文字工具

extension View {
    /// 微标签: 全大写 + 字距, 用于 "LOSSLESS / 独占输出" 这类元信息。
    func dsMicroLabel(_ color: Color = DS.Palette.textTertiary) -> some View {
        self.font(DS.TypeScale.micro)
            .tracking(DS.Tracking.micro)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

struct ScrollContentFade: ViewModifier {
    var top: CGFloat = 24
    var bottom: CGFloat = 0
    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                if top > 0 {
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: top)
                }
                Color.white
                if bottom > 0 {
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: bottom)
                }
            }
        }
    }
}

extension View {
    func dsScrollFade(top: CGFloat = 24, bottom: CGFloat = 0) -> some View {
        modifier(ScrollContentFade(top: top, bottom: bottom))
    }
}
