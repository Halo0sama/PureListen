import AppKit
import SwiftUI

// MARK: - 品牌标记

/// 净听标记: 一张唱片 —— 外圈留一道约 20° 的开口(开口在右上 1-2 点钟方向),
/// 中心是唱针落点。与 `docs/design/appicon` 里的应用图标同源。
struct DSBrandMark: View {
    var size: CGFloat = 22
    var tint: Color? = nil

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2
            let color = tint ?? DS.Palette.textPrimary
            let ringWidth = max(1.0, radius * 0.20)

            // 外圈: 扫过 340°, 在 305° 附近留出 20° 的开口。
            var ring = Path()
            ring.addArc(center: center, radius: radius - ringWidth / 2,
                        startAngle: .degrees(315), endAngle: .degrees(655),
                        clockwise: false)
            context.stroke(ring, with: .color(color),
                           style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))

            // 中心点: 唱针落点。
            let dot = radius * 0.24
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot,
                                                width: dot * 2, height: dot * 2)),
                         with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 分区标题

struct DSSectionHeader: View {
    var title: String
    var detail: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(title)
                .font(DS.TypeScale.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DS.Palette.textSecondary)
            if let detail {
                Text(detail)
                    .font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DS.Space.xxs)
    }
}

// MARK: - 徽标

enum DSTone {
    case neutral, accent, mint, amber, rose

    func foreground(_ tint: Color, isDark: Bool) -> Color {
        switch self {
        case .neutral: return DS.Palette.textSecondary
        case .accent: return isDark ? tint : tint.opacity(0.95)
        case .mint: return DS.Palette.mint
        case .amber: return DS.Palette.amber
        case .rose: return DS.Palette.rose
        }
    }

    func background(_ tint: Color) -> Color {
        switch self {
        case .neutral: return DS.Palette.surfaceSelected
        case .accent: return tint.opacity(0.16)
        case .mint: return DS.Palette.mint.opacity(0.15)
        case .amber: return DS.Palette.amber.opacity(0.16)
        case .rose: return DS.Palette.rose.opacity(0.16)
        }
    }
}

/// 小徽标: "无损" "44.1kHz" "位完美"。
struct DSChip: View {
    var text: String
    var systemImage: String? = nil
    var tone: DSTone = .neutral
    var compact: Bool = false
    @Environment(\.albumTint) private var tint
    @Environment(\.dsIsDark) private var isDark

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
                .tracking(0.2)
        }
        .foregroundStyle(tone.foreground(tint, isDark: isDark))
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background {
            Capsule(style: .continuous).fill(tone.background(tint))
        }
        .overlay {
            if case .neutral = tone {
                Capsule(style: .continuous).strokeBorder(DS.Palette.hairline, lineWidth: 0.8)
            }
        }
    }
}

// MARK: - 按钮

/// 圆形图标按钮, 悬停时浮出一层玻璃。
struct DSIconButton: View {
    var systemName: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 12
    var isActive: Bool = false
    var help: String? = nil
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.albumTint) private var tint

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hovering ? DS.Palette.surfaceHover : .clear)
                if isActive { Circle().fill(tint.opacity(0.16)) }
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isActive ? tint : DS.Palette.textSecondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.quick) { hovering = value }
        }
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }
}

/// 胶囊按钮: 玻璃底、可选强调色。
struct DSPillButton: View {
    var title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var tint: Color? = nil
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.albumTint) private var albumTint
    @Environment(\.dsIsDark) private var isDark

    private var accent: Color { tint ?? albumTint }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(prominent ? (isDark ? Color.black : Color.white)
                                       : DS.Palette.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 26)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? (isDark ? Color.white.opacity(hovering ? 1.0 : 0.94)
                                              : Color.black.opacity(hovering ? 0.92 : 0.86))
                                    : (hovering ? DS.Palette.surfaceSelected
                                                : DS.Palette.surfaceHover))
                    .overlay {
                        if !prominent {
                            Capsule(style: .continuous)
                                .strokeBorder(DS.Palette.hairline, lineWidth: 0.8)
                        }
                    }
                    .shadow(color: prominent ? .black.opacity(0.28) : .clear,
                            radius: 8, y: 2)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(DS.Motion.quick) { hovering = value } }
    }
}

/// 主播放按钮: 玻璃球 + 强调色。
struct DSPlayButton: View {
    var isPlaying: Bool
    var size: CGFloat = 44
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.albumTint) private var tint
    @Environment(\.dsIsDark) private var isDark

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isDark ? Color.white.opacity(0.96) : Color.black.opacity(0.86))
                    .shadow(color: .black.opacity(0.30), radius: 10, y: 3)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(isDark ? Color.black : Color.white)
                    .offset(x: isPlaying ? 0 : size * 0.02)
            }
            .frame(width: size, height: size)
            .scaleEffect(hovering ? 1.04 : 1)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(DS.Motion.quick) { hovering = value } }
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }
}

// MARK: - 分段选择

/// 胶囊分段控件 —— macOS 27 Golden Gate 的 Liquid Glass 外观。
///
/// 交互对齐官方 Liquid Glass：整条是玻璃胶囊，选中项是一枚更亮的玻璃胶囊；
/// 按住并拖动时，选中胶囊会像液态透镜一样跟随指针滑动，松手后落到指针所在分段。
struct DSSegmented<Item: Hashable>: View {
    var items: [Item]
    var title: (Item) -> String
    @Binding var selection: Item
    var height: CGFloat = 30
    /// 悬停到的分段(用于预加载对应页面，例如 B 站面板)。
    var onHover: ((Item?) -> Void)? = nil

    @Environment(\.dsIsDark) private var isDark
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassLensDebugPoint) private var debugPoint
    @State private var hoveringItem: Item?
    @State private var pressed = false
    @State private var pointer: CGPoint?

    private var isPressed: Bool { pressed || debugPoint != nil }
    private var activePoint: CGPoint? { debugPoint ?? pointer }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(DS.Motion.page) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? DS.Palette.textPrimary
                                                    : DS.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 6)
                        .background {
                            if !isPressed, hoveringItem == item, !isSelected {
                                Capsule(style: .continuous)
                                    .fill(DS.Palette.surfaceHover)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    withAnimation(DS.Motion.quick) {
                        hoveringItem = inside ? item : (hoveringItem == item ? nil : hoveringItem)
                    }
                    onHover?(inside ? item : nil)
                }
            }
        }
        .padding(3)
        .background {
            GeometryReader { geo in
                selectionLayer(size: geo.size)
            }
        }
        .modifier(SegmentedGlassTrack(reduceTransparency: reduceTransparency, height: height))
        .modifier(GlassPointerTracking(enabled: !reduceTransparency,
                                       pressed: $pressed,
                                       point: $pointer,
                                       onPressEnded: commit))
    }

    // MARK: 布局

    private func metrics(in size: CGSize) -> (segWidth: CGFloat, pillWidth: CGFloat, selectedX: CGFloat) {
        let count = CGFloat(max(items.count, 1))
        let usable = max(size.width - 6, 1)
        let segWidth = usable / count
        let pillWidth = max(segWidth - 4, 10)
        let index = CGFloat(items.firstIndex(of: selection) ?? 0)
        return (segWidth, pillWidth, 3 + segWidth * (index + 0.5))
    }

    /// 选中胶囊 / 指针透镜所在的背景层：在文字与按钮之下、玻璃之上。
    @ViewBuilder
    private func selectionLayer(size: CGSize) -> some View {
        let m = metrics(in: size)
        let pillHeight = max(height - 8, 10)

        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(DS.Palette.surfaceSelected)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                }
                .frame(width: m.pillWidth, height: pillHeight)
                .position(x: m.selectedX, y: size.height / 2)
                .allowsHitTesting(false)
        } else {
            // 上下与左右均可伸出轨道 8pt。
            let lensScale: CGFloat = isPressed ? 1.40 : 1
            let overhang: CGFloat = 8
            let pressedX: CGFloat = {
                guard isPressed, let point = activePoint else { return m.selectedX }
                // 放大后的透镜允许越出轨道边缘一点（官方那种"出框"感），但不要越出弹窗。
                let half = m.pillWidth * lensScale / 2
                let lower = max(half - overhang, 0)
                let upper = min(size.width - half + overhang, size.width)
                return min(max(point.x, lower), upper)
            }()

            ZStack {
                // 选择胶囊：拖动时跟随指针，松手弹到目标分段
                Capsule(style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.17) : Color.white.opacity(0.94))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isPressed
                                    ? LinearGradient(colors: [Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.45),
                                                              Color.white.opacity(0.45),
                                                              Color(red: 1.0, green: 0.55, blue: 0.90).opacity(0.25)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.white.opacity(isDark ? 0.44 : 0.9),
                                                              Color.white.opacity(isDark ? 0.06 : 0.2)],
                                                     startPoint: .top, endPoint: .bottom),
                                lineWidth: isPressed ? 1.2 : 0.8)
                    }
                    .frame(width: m.pillWidth * lensScale,
                           height: isPressed ? height + overhang * 2 : pillHeight)
                    .shadow(color: .black.opacity(isDark ? (isPressed ? 0.40 : 0.30)
                                                        : (isPressed ? 0.20 : 0.12)),
                            radius: isPressed ? 10 : 3,
                            y: isPressed ? 3 : 1)
                    .position(x: pressedX, y: size.height / 2)
                    .animation(DS.Motion.standard, value: pressedX)
                    .animation(DS.Motion.press, value: isPressed)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: 按拖选择

    private func commit(_ point: CGPoint, _ size: CGSize) {
        guard !items.isEmpty else { return }
        let m = metrics(in: size)
        let raw = Int(((point.x - 3) / max(m.segWidth, 1)).rounded(.down))
        let clamped = min(max(raw, 0), items.count - 1)
        let target = items[clamped]
        guard target != selection else { return }
        withAnimation(DS.Motion.page) { selection = target }
    }
}

/// 分段控件的玻璃底座：正常外观用真实 Liquid Glass；降低透明度时退化为实体胶囊。
private struct SegmentedGlassTrack: ViewModifier {
    var reduceTransparency: Bool
    var height: CGFloat
    @Environment(\.dsIsDark) private var isDark

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(DS.Palette.surfaceSelected)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                        }
                }
        } else {
            content
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(isDark ? 0.26 : 0.75),
                                                    Color.white.opacity(isDark ? 0.06 : 0.2)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        }
    }
}

// MARK: - 进度 / 音量

/// 可拖动的细进度条。悬停时变粗并浮出圆点, 按下去跟手。
struct DSSeekBar: View {
    /// 0...1
    var progress: Double
    var tint: Color
    var height: CGFloat = 4
    var showsThumbAlways: Bool = false
    var onScrub: (Double) -> Void = { _ in }
    var onScrubbing: ((Double) -> Void)? = nil

    @State private var hovering = false
    @State private var dragging: Double? = nil

    private var active: Bool { hovering || dragging != nil }
    private var trackHeight: CGFloat { active ? height + 2 : height }
    private var thumbSize: CGFloat { active || showsThumbAlways ? 11 : 0 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let value = min(max(dragging ?? progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(DS.Palette.surfaceSelected)
                    .frame(height: trackHeight)
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.85)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, width * value), height: trackHeight)
                if thumbSize > 0 {
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(x: min(max(0, width * value - thumbSize / 2), width - thumbSize))
                }
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / max(width, 1), 0), 1)
                        dragging = fraction
                        onScrubbing?(fraction)
                    }
                    .onEnded { gesture in
                        let fraction = min(max(gesture.location.x / max(width, 1), 0), 1)
                        onScrub(fraction)
                        dragging = nil
                    }
            )
            .onHover { value in
                withAnimation(DS.Motion.quick) { hovering = value }
            }
            .animation(DS.Motion.quick, value: trackHeight)
        }
        .frame(height: 18)
    }
}

/// 音量条: 图标随音量变化。
struct DSVolumeBar: View {
    var volume: Double
    var tint: Color
    var onVolume: (Double) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: volumeIcon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 13)
                .contentTransition(.symbolEffect(.replace))
            DSSeekBar(progress: volume, tint: tint, height: 3,
                      onScrub: onVolume, onScrubbing: onVolume)
        }
    }

    private var volumeIcon: String {
        switch volume {
        case 0.001...: return volume < 0.34 ? "speaker.wave.1.fill"
            : volume < 0.7 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        default: return "speaker.slash.fill"
        }
    }
}

// MARK: - 波形 / 动效

/// 装饰性波形: 播放时缓慢起伏, 暂停时压平。
///
/// 它不读取任何音频数据 —— 净听的目标是"让音乐从耳机里出去", 界面只负责安静地呼吸。
struct DSWaveform: View {
    var isPlaying: Bool
    var tint: Color
    var bars: Int = 5
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 减少动态效果: 波形静止在一帧, 不做循环动画。
        if isPlaying && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                barsView(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            barsView(time: 1.7).opacity(isPlaying ? 0.9 : 0.55)
        }
    }

    private func barsView(time: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<bars, id: \.self) { index in
                let phase = Double(index) * 0.9
                let wave = isPlaying ? (sin(time * 2.4 + phase) * 0.5 + 0.5) : 0.35
                let secondary = isPlaying ? (sin(time * 1.3 + phase * 1.7) * 0.5 + 0.5) : 0.5
                let height = maxHeight * (0.22 + 0.78 * (wave * 0.65 + secondary * 0.35))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: barWidth, height: height)
            }
        }
        .frame(height: maxHeight)
    }
}

/// 单个"正在播放"指示(列表里用)。
struct DSPlayingIndicator: View {
    var isPlaying: Bool
    var tint: Color

    var body: some View {
        DSWaveform(isPlaying: isPlaying, tint: tint, bars: 4, barWidth: 2, maxHeight: 11)
    }
}

// MARK: - 列表行

/// 通用列表行: 悬停高亮、可选选中态、左侧内容 + 主副标题 + 右侧内容。
struct DSListRow<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    var height: CGFloat = DS.Size.rowHeight
    var action: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @State private var hovering = false
    @Environment(\.albumTint) private var tint

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.l) {
                leading()
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(DS.TypeScale.rowTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s)
                trailing()
            }
            .padding(.horizontal, DS.Space.m)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(background)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.quick) { hovering = value }
        }
    }

    private var background: Color {
        if isSelected { return tint.opacity(0.07) }
        return hovering ? DS.Palette.surfaceHover : .clear
    }
}

// MARK: - 设置行

/// 设置面板一行: 标题 + 说明 (+ 辅助控件)。
struct DSSettingRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.albumTint) private var albumTint

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.l) {
            if let systemImage {
                DSGlyphTile(systemName: systemImage, tint: tint ?? albumTint, size: 24)
            }
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(DS.TypeScale.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: DS.Space.m)
            trailing()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, DS.Space.m)
    }
}

/// 设置里的小图标块: 圆角方块 + 彩色符号, Golden Gate 侧边栏的视觉语言。
struct DSGlyphTile: View {
    var systemName: String
    var tint: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.62)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            }
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.28), radius: 3, y: 1)
    }
}

// MARK: - 状态点

/// 信号链路上的一个节点圆点(呼吸动画)。
struct DSStatusDot: View {
    var color: Color
    var isLive: Bool = true
    var diameter: CGFloat = 7

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(color.opacity(0.28))
                    .frame(width: diameter * 2.1, height: diameter * 2.1)
                    .blur(radius: 1.5)
            }
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
                }
        }
        .frame(width: diameter * 2.1, height: diameter * 2.1)
    }
}

// MARK: - 分隔线

struct DSSoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Palette.hairline)
            .frame(height: 1)
    }
}

// MARK: - 空状态

struct DSEmptyState: View {
    var systemImage: String
    var title: String
    var message: String? = nil
    var action: (() -> Void)? = nil
    var actionTitle: String = "重试"

    @Environment(\.albumTint) private var tint

    var body: some View {
        VStack(spacing: DS.Space.l) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 56, height: 56)
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(tint.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 3) {
                Text(title)
                    .font(DS.TypeScale.body)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.Palette.textPrimary)
                if let message {
                    Text(message)
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            if let action {
                DSPillButton(title: actionTitle, prominent: false, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxl)
        .padding(.horizontal, DS.Space.xl)
    }
}

// MARK: - 搜索框 / 输入框

struct DSSearchField: View {
    var placeholder: String
    @Binding var text: String
    var isBusy: Bool = false
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.albumTint) private var tint

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(focused ? tint : DS.Palette.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.TypeScale.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .focused($focused)
                .focusEffectDisabled()
                .onSubmit(onSubmit)
            if isBusy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }

        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
                .fill(DS.Palette.surfaceHover)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
                        .strokeBorder(focused ? DS.Palette.hairlineStrong.opacity(0.35)
                                              : DS.Palette.hairline,
                                      lineWidth: 1)
                }
        }
        .animation(DS.Motion.quick, value: focused)
        .animation(DS.Motion.quick, value: text.isEmpty)
    }
}

// MARK: - 开关

/// 自绘开关: 与 macOS 27 原生 switch 同形(34×20 胶囊 + 白色圆钮), 但用固定品牌色。
///
/// 为什么不用系统 `Toggle(.switch)`: ① 系统开关跟随「系统强调色」, 会引入第二种主色;
/// ② 窗口非 key 时系统控件会画成灰色, 截图模式无法稳定激活动作。
struct DSSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = DS.Palette.brandAccent
    var width: CGFloat = 34
    var height: CGFloat = 20

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsIsDark) private var isDark

    var body: some View {
        Button {
            guard !reduceMotion else { isOn.toggle(); return }
            withAnimation(DS.Motion.press) { isOn.toggle() }
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? tint : DS.Palette.surfaceSelected)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.12)
                                             : Color.black.opacity(0.06),
                                      lineWidth: 0.8)
                }
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.28), radius: 1.4, y: 0.6)
                }
                .frame(width: width, height: height)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .brightness(hovering ? 0.04 : 0)
        .animation(DS.Motion.standard, value: isOn)
        .onHover { value in
            withAnimation(DS.Motion.quick) { hovering = value }
        }
        .accessibilityElement()
        .accessibilityLabel(isOn ? "已开启" : "已关闭")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 玻璃工具组(Golden Gate toolbar clusters)

/// 独立的玻璃圆钮: 工具栏里那种一颗一颗的小玻璃圆。
struct DSGlassIconButton: View {
    var systemName: String
    var help: String
    var diameter: CGFloat = 30
    var iconSize: CGFloat = 11
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dsIsDark) private var isDark

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .frame(width: diameter - 10, height: diameter - 10)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(5)
        .modifier(GlassToolbarTrack(reduceTransparency: reduceTransparency, isDark: isDark,
                                    hovered: hovering, shape: AnyShape(Capsule(style: .continuous))))
        .modifier(GlassIconPointerLens(enabled: !reduceTransparency, pressScale: 1.20))
        .onHover { inside in
            withAnimation(DS.Motion.quick) { hovering = inside }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 带文字的玻璃胶囊按钮(例如「窗口模式」)。
struct DSGlassPillButton: View {
    var title: String
    var systemImage: String? = nil
    var height: CGFloat = 30
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dsIsDark) private var isDark

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: height - 10)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(5)
        .modifier(GlassToolbarTrack(reduceTransparency: reduceTransparency, isDark: isDark,
                                    hovered: hovering, shape: AnyShape(Capsule(style: .continuous))))
        .modifier(GlassIconPointerLens(enabled: !reduceTransparency, pressScale: 1.14))
        .onHover { inside in
            withAnimation(DS.Motion.quick) { hovering = inside }
        }
        .accessibilityLabel(title)
    }
}

/// 工具栏玻璃底: 正常用真实 Liquid Glass, 降低透明度时退化为实体胶囊。
private struct GlassToolbarTrack: ViewModifier {
    var reduceTransparency: Bool
    var isDark: Bool
    var hovered: Bool
    var shape: AnyShape

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(hovered ? DS.Palette.surfaceSelected : DS.Palette.surface)
                        .overlay { shape.stroke(DS.Palette.hairline, lineWidth: 1) }
                }
        } else {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [Color.white.opacity(isDark ? 0.24 : 0.7),
                                                Color.white.opacity(isDark ? 0.05 : 0.15)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .brightness(hovered ? 0.02 : 0)
        }
    }
}

/// 小圆钮/胶囊钮的指针透镜: 按下时整枚玻璃胶囊放大成透镜。
private struct GlassIconPointerLens: ViewModifier {
    var enabled: Bool
    var pressScale: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.glassPointerLens(in: Capsule(style: .continuous),
                                     pressScale: pressScale)
        } else {
            content
        }
    }
}
