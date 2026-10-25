import SwiftUI
import PureListenCore

// MARK: - 设置页排版度量
//
// 设置页有两种呼出方式: 菜单栏 popover(372 宽, 内容从浮动播放台下穿过) 与
// 主窗口内容区(>700 宽)。两者共用同一套结构与组件, 只切换度量:
// popover 紧凑、window 宽松。所有颜色 / 字体 / 圆角仍来自 DS 令牌。

struct SettingsMetrics {
    var layout: SettingsLayout

    /// 卡片最大宽度 (nil = 撑满可用宽度)。
    var cardMaxWidth: CGFloat?
    /// 页面左右留白。
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    /// popover 下要为空中的播放台让位。
    var bottomPadding: CGFloat
    var sectionSpacing: CGFloat
    var cardRadius: CGFloat
    var cardVerticalPadding: CGFloat
    /// 卡片内一行标题的左右留白(也就是分隔线的内缩量)。
    var rowHorizontalPadding: CGFloat
    var rowVerticalPadding: CGFloat
    /// 标题与说明之间。
    var rowSpacing: CGFloat
    /// 文字与右侧控件之间。
    var controlSpacing: CGFloat
    var headerFont: Font
    var headerDetailFont: Font
    var headerBottomPadding: CGFloat
    var titleFont: Font
    var subtitleFont: Font
    var footnoteFont: Font
    var bodyFont: Font
    var segmentedHeight: CGFloat

    static func forLayout(_ layout: SettingsLayout) -> SettingsMetrics {
        switch layout {
        case .popover:
            return SettingsMetrics(
                layout: .popover,
                cardMaxWidth: nil,
                horizontalPadding: DS.Space.popoverPadding,
                topPadding: DS.Space.m,
                bottomPadding: 138,
                sectionSpacing: DS.Space.xl,
                cardRadius: DS.Radius.card,
                cardVerticalPadding: DS.Space.xs,
                rowHorizontalPadding: DS.Space.l,
                rowVerticalPadding: 8,
                rowSpacing: 1.5,
                controlSpacing: DS.Space.l,
                headerFont: .system(size: 11, weight: .semibold),
                headerDetailFont: .system(size: 10, weight: .medium),
                headerBottomPadding: DS.Space.s,
                titleFont: DS.TypeScale.body,
                subtitleFont: DS.TypeScale.caption,
                footnoteFont: .system(size: 10.5, weight: .regular),
                bodyFont: DS.TypeScale.caption,
                segmentedHeight: 28
            )
        case .window:
            return SettingsMetrics(
                layout: .window,
                cardMaxWidth: 620,
                horizontalPadding: DS.Space.windowPadding,
                topPadding: DS.Space.s,
                bottomPadding: DS.Space.xxl * 2,
                sectionSpacing: DS.Space.xxl,
                cardRadius: DS.Radius.card,
                cardVerticalPadding: DS.Space.s,
                rowHorizontalPadding: DS.Space.xl,
                rowVerticalPadding: 11,
                rowSpacing: 2,
                controlSpacing: DS.Space.xl,
                headerFont: .system(size: 12.5, weight: .semibold),
                headerDetailFont: .system(size: 10.5, weight: .medium),
                headerBottomPadding: DS.Space.m,
                titleFont: .system(size: 13, weight: .regular),
                subtitleFont: .system(size: 11.5, weight: .regular),
                footnoteFont: .system(size: 11, weight: .regular),
                bodyFont: .system(size: 11.5, weight: .regular),
                segmentedHeight: 32
            )
        }
    }
}

// MARK: - 分区 (标题 + 卡片)

/// 一组设置: 卡片外面一枚克制的小标题 —— macOS 27 系统设置的层级语言。
struct SettingsSection<Content: View>: View {
    var title: String
    var detail: String? = nil
    var live: Bool = false
    var trailing: AnyView? = nil
    var metrics: SettingsMetrics
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: title, detail: detail, live: live,
                                  trailing: trailing, metrics: metrics)
            SettingsCard(metrics: metrics) { content() }
        }
    }
}

struct SettingsSectionHeader: View {
    var title: String
    var detail: String? = nil
    var live: Bool = false
    var trailing: AnyView? = nil
    var metrics: SettingsMetrics

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title)
                .font(metrics.headerFont)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: DS.Space.s)
            if let trailing {
                trailing
            } else if let detail {
                HStack(spacing: DS.Space.xs) {
                    if live {
                        DSStatusDot(color: DS.Palette.mint, isLive: false, diameter: 5)
                    }
                    Text(detail)
                        .font(metrics.headerDetailFont)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, DS.Space.xs)
        .padding(.bottom, metrics.headerBottomPadding)
    }
}

// MARK: - 卡片表面

/// window 布局专用实体表面: 不透明, 不让窗口的封面氛围透上来, 卡片明确"浮"在背景上。
enum SettingsSurface {
    static let solid = Color.dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.94),
        // #151517 + 白 6%: 深色下是一块比画布略亮的浮板, 但不透出背景。
        dark: NSColor(srgbRed: 0.123, green: 0.123, blue: 0.130, alpha: 1)
    )

    static let solidStroke = Color.dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.045),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.075)
    )
}

/// 实体表面卡片: 设置项一律落在实体表面上, 不使用玻璃 (可读性优先)。
struct SettingsCard<Content: View>: View {
    var metrics: SettingsMetrics
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, metrics.cardVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: metrics.cardRadius, style: .continuous)
                Group {
                    if metrics.layout == .window {
                        shape.fill(SettingsSurface.solid)
                            .overlay { shape.strokeBorder(SettingsSurface.solidStroke, lineWidth: 1) }
                    } else {
                        shape.fill(DS.Palette.surface)
                            .overlay { shape.strokeBorder(DS.Palette.hairline, lineWidth: 1) }
                    }
                }
            }
    }
}

// MARK: - 行

/// 一行设置: 左侧标题 / 说明, 右侧控件。
struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    /// 标题后面的小徽标, 例如「实验」。
    var badge: String? = nil
    var badgeTone: DSTone = .neutral
    var metrics: SettingsMetrics
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: metrics.controlSpacing) {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                HStack(spacing: DS.Space.s) {
                    Text(title)
                        .font(metrics.titleFont)
                        .foregroundStyle(DS.Palette.textPrimary)
                    if let badge {
                        DSChip(text: badge, tone: badgeTone, compact: true)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(metrics.subtitleFont)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: DS.Space.m)
            trailing()
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
    }
}

/// 行之间的极细分隔线 (两端内缩, 与系统设置一致)。
struct SettingsRowDivider: View {
    var metrics: SettingsMetrics

    var body: some View {
        DSSoftDivider()
            .padding(.horizontal, metrics.rowHorizontalPadding)
    }
}

/// 卡片内的一行补充说明(权限提示等)。
struct SettingsFootnote<Content: View>: View {
    var metrics: SettingsMetrics
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .padding(.bottom, metrics.rowVerticalPadding)
    }
}

// MARK: - 开关

/// 设置开关: 统一走自绘的 `DSSwitch` —— 固定品牌色开态, 不随封面 / 系统强调色变化。
struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        DSSwitch(isOn: $isOn)
    }
}

// MARK: - 按钮

/// 危险动作的胶囊按钮(退出登录 / 清除缓存等)。
struct SettingsDangerButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.Palette.rose)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Palette.rose.opacity(hovering ? 0.20 : 0.11))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Palette.rose.opacity(hovering ? 0.45 : 0.28), lineWidth: 0.8)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(DS.Motion.quick) { hovering = value } }
    }
}

/// 「退出净听」: 整行宽度的 rose 描边胶囊。
struct SettingsQuitButton: View {
    var metrics: SettingsMetrics
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "power")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("退出净听")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DS.Palette.rose.opacity(hovering ? 1 : 0.92))
            .frame(maxWidth: .infinity)
            .frame(height: metrics.layout == .window ? 34 : 30)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Palette.rose.opacity(hovering ? 0.12 : 0.05))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Palette.rose.opacity(hovering ? 0.50 : 0.30), lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(DS.Motion.quick) { hovering = value } }
        .help("释放独占输出并退出净听")
    }
}

/// 小型中性胶囊按钮 (清除缓存 / 重新扫码这类次级动作)。
struct SettingsSmallButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.albumTint) private var tint

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(hovering ? DS.Palette.surfaceSelected : DS.Palette.surfaceHover)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 0.8)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(DS.Motion.quick) { hovering = value } }
    }
}

// MARK: - 环境注入 (截图用)

private struct SettingsForceMediaKeyWarningKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SettingsPreviewScrollKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// 截图专用: 强制显示媒体键权限提示(权限状态与机器相关, 保证出图稳定)。
    var settingsForceMediaKeyWarning: Bool {
        get { self[SettingsForceMediaKeyWarningKey.self] }
        set { self[SettingsForceMediaKeyWarningKey.self] = newValue }
    }

    /// 截图专用: 打开设置页时滚到某个分区, 便于逐个区域走查。
    var settingsPreviewScrollTarget: String? {
        get { self[SettingsPreviewScrollKey.self] }
        set { self[SettingsPreviewScrollKey.self] = newValue }
    }
}
