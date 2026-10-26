import SwiftUI
import PureListenCore

// MARK: - 侧边栏

/// edge-to-edge 侧边栏: 延伸到窗口左边缘与顶部, 顶部留 52pt 给红绿灯。
///
/// 它是 chrome 层(材质底), 内容层没有任何玻璃 —— 于是界面的层次只有两层:
/// 背景 → 侧边栏/内容 → 浮动的音质胶囊。
struct WindowSidebar: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var router: WindowRouter

    @Environment(\.albumTint) private var tint
    @Environment(\.dsIsDark) private var isDark
    @Namespace private var highlight
    @State private var hoveringDevice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 红绿灯区域(真实窗口按钮浮在这上面)。
            Color.clear
                .frame(height: DS.Size.toolbarHeight)

            brand
                .padding(.horizontal, DS.Space.xxl - DS.Space.xs)

            Spacer()
                .frame(height: DS.Space.xxl)

            VStack(spacing: DS.Space.xxs) {
                ForEach(NowPlayingSection.allCases, id: \.self) { section in
                    WindowSidebarNavRow(
                        section: section,
                        isSelected: router.section == section,
                        tint: tint,
                        isDark: isDark,
                        namespace: highlight
                    ) {
                        router.select(section)
                    }
                }
            }
            .padding(.horizontal, DS.Space.m)

            Spacer(minLength: DS.Space.xxl)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) { backdrop }
        .overlay(alignment: .trailing) { separator }
        .clipped()
    }

    // MARK: 品牌

    private var brand: some View {
        HStack(spacing: DS.Space.m) {
            DSBrandMark(size: 19, tint: DS.Palette.textPrimary)
            VStack(alignment: .leading, spacing: 0) {
                Text("净听")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("purelisten")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 底

    private var backdrop: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.ultraThinMaterial)

            if isDark {
                LinearGradient(colors: [.black.opacity(0.30), .black.opacity(0.38)],
                               startPoint: .top, endPoint: .bottom)
                // 红绿灯与品牌区再压一点, 顶部更稳。
                LinearGradient(colors: [.black.opacity(0.20), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
            } else {
                LinearGradient(colors: [.white.opacity(0.46), .white.opacity(0.30)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.white.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(DS.Palette.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    // MARK: 底部状态

    private var deviceName: String {
        state.selectedDevice?.name ?? (state.autoDevice ? "未选择输出" : "指定设备离线")
    }

    private var deviceSymbol: String {
        let name = deviceName.lowercased()
        if name.contains("耳机") || name.contains("headphone") || name.contains("earbud") {
            return "headphones"
        }
        if name.contains("dac") || name.contains("usb") {
            return "cable.connector"
        }
        return "hifispeaker"
    }

    private var deviceDetail: String {
        guard let device = state.selectedDevice else {
            return state.autoDevice ? "自动选择 · 点击切换" : "等待连接 · 点击切换"
        }
        let rate = state.playerState == .playing && state.trackStatus.deviceRate > 0
            ? state.trackStatus.deviceRate
            : Int(device.currentRate)
        let routing = state.autoDevice ? "自动跟随" : "手动指定"
        return "\(WindowFormatting.rate(rate)) · \(routing)"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            DSSoftDivider()
                .opacity(0.9)

            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xs + 1) {
                    Text("输出设备")
                        .dsMicroLabel(DS.Palette.textTertiary)
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: deviceSymbol)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(deviceName)
                            .font(.system(size: 11.5, weight: .medium))
                            .tracking(DS.Tracking.tight)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(deviceDetail)
                        .font(DS.TypeScale.meta)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(hoveringDevice ? DS.Palette.surfaceHover : .clear)
            }
            .contentShape(Rectangle())
            .overlay {
                WindowDeviceMenu(state: state, deviceName: deviceName)
            }
            .padding(.horizontal, -8)
            .onHover { value in
                withAnimation(DS.Motion.quick) { hoveringDevice = value }
            }
            .help("选择输出设备；切换后暂停，点击播放继续")
            .accessibilityLabel("切换输出设备，当前\(deviceName)")
            .accessibilityIdentifier("window-output-device-menu")
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.bottom, DS.Space.xl)
    }
}

// MARK: - 导航行

/// 侧边栏的一行导航: 图标 + 文字, 悬停浮出浅底, 选中用音乐色浅底滑动。
struct WindowSidebarNavRow: View {
    var section: NowPlayingSection
    var isSelected: Bool
    var tint: Color
    var isDark: Bool
    var namespace: Namespace.ID
    var action: () -> Void

    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.l - DS.Space.xxs) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? tint : DS.Palette.textSecondary)
                Text(section.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(isSelected ? tint : DS.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.m + DS.Space.xxs)
            .frame(height: 32)
            .background {
                ZStack {
                    if hovering && !isSelected {
                        shape.fill(DS.Palette.surfaceHover.opacity(0.78))
                    }
                    if isSelected {
                        shape.fill(tint.opacity(isDark ? 0.17 : 0.13))
                            .matchedGeometryEffect(id: "window-sidebar-selection",
                                                   in: namespace)
                    }
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.quick) { hovering = value }
        }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
