import AppKit
import SwiftUI
import PureListenCore

/// 设置页布局: popover 内单列紧凑, 窗口内宽内容区。
enum SettingsLayout {
    case popover
    case window
}

/// 设置页。
///
/// 视觉目标: macOS 27 系统设置 —— 卡片是实体表面、分组标题克制、行内信息分层清晰、
/// 开关用系统原生控件。它自己不画页头与返回按钮(由 popover 顶栏 / 窗口页面提供),
/// 也不画背景(由呼出方的 AlbumTintProvider 提供), 因此两种布局共用同一份内容。
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.settingsForceMediaKeyWarning) private var forceMediaKeyWarning
    @Environment(\.settingsPreviewScrollTarget) private var previewScrollTarget

    var layout: SettingsLayout = .popover

    private var metrics: SettingsMetrics { .forLayout(layout) }

    // MARK: - 主体

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    qualitySection.id("settings-quality")
                    outputSection.id("settings-output")
                    protectionSection.id("settings-protection")
                    biliSection.id("settings-bili")
                    cacheSection.id("settings-cache")
                    accountSection.id("settings-account")
                    aboutSection.id("settings-about")
                }
                .frame(maxWidth: metrics.cardMaxWidth ?? .infinity, alignment: .leading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onAppear { scrollToPreviewTarget(proxy) }
            .onChange(of: previewScrollTarget) { _, _ in scrollToPreviewTarget(proxy) }
        }
    }

    /// 截图专用: 滚到指定分区(真实使用时 previewScrollTarget 恒为 nil)。
    private func scrollToPreviewTarget(_ proxy: ScrollViewProxy) {
        guard let target = previewScrollTarget else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // MARK: - 音质

    private static let qualityOrder: [NCLevel] = [.hires, .lossless, .exhigh, .standard]

    private var qualitySection: some View {
        SettingsSection(title: "音质",
                        trailing: AnyView(qualityChip),
                        metrics: metrics) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                DSSegmented(items: Self.qualityOrder,
                            title: shortQualityTitle,
                            selection: qualityBinding,
                            height: metrics.segmentedHeight)
                Text(qualityNote)
                    .font(metrics.subtitleFont)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, metrics.rowVerticalPadding)
        }
    }

    /// 当前音质: 全页唯一一处品牌色, 让"选中"这件事一眼可见。
    private var qualityChip: some View {
        Text(state.level.label)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(DS.Palette.brandAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Palette.brandAccent.opacity(0.14))
            }
    }

    private var qualityBinding: Binding<NCLevel> {
        Binding(get: { state.level }, set: { state.level = $0 })
    }

    private func shortQualityTitle(_ level: NCLevel) -> String {
        switch level {
        case .hires: return "Hi-Res"
        case .lossless: return "无损"
        case .exhigh: return "极高"
        case .standard: return "标准"
        }
    }

    private var qualityNote: String {
        switch state.level {
        case .hires:
            return "优先请求 Hi-Res 母带；内置 3.5mm 孔最高 96kHz，192kHz 母带会自动降采样。"
        case .lossless:
            return "优先无损 FLAC，按音源原始采样率独占输出，不经过系统混音器。"
        case .exhigh:
            return "320kbps 有损音源，网络受限时使用。"
        case .standard:
            return "128kbps 有损音源，仅在网络极差时使用。"
        }
    }

    // MARK: - 输出

    private var outputSection: some View {
        SettingsSection(title: "输出",
                        detail: state.autoDevice ? "自动" : "手动",
                        metrics: metrics) {
            SettingsRow(title: "输出设备", subtitle: deviceSubtitle, metrics: metrics) {
                Picker("", selection: deviceSelection) {
                    Text("自动").tag(0)
                    ForEach(state.devices) { device in
                        Text(device.name).tag(Int(device.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                // 用固定品牌色, 避免菜单按钮跟随系统强调色(系统蓝/系统粉)。
                .tint(DS.Palette.brandAccent)
            }
            SettingsRowDivider(metrics: metrics)
            SettingsRow(title: "启动时自动继续上次歌单",
                        subtitle: "打开净听后接着播放上次的歌单",
                        metrics: metrics) {
                SettingsToggle(isOn: $state.autoResume)
            }
        }
    }

    private var deviceSubtitle: String {
        if state.autoDevice { return "自动跟随耳机插拔切换" }
        guard let device = state.selectedDevice else { return "手动指定输出设备" }
        let rate = device.currentRate > 0
            ? String(format: " · %.1fkHz", device.currentRate / 1000)
            : ""
        return "已锁定 \(device.name)\(rate)"
    }

    private var deviceSelection: Binding<Int> {
        Binding(
            get: { state.autoDevice ? 0 : Int(state.selectedDevice?.id ?? 0) },
            set: { newValue in
                if newValue == 0 {
                    state.autoDevice = true
                } else if let device = state.devices.first(where: { Int($0.id) == newValue }) {
                    state.selectDevice(device)
                }
            }
        )
    }

    // MARK: - 播放保护

    private var protectionSection: some View {
        SettingsSection(title: "播放保护", metrics: metrics) {
            SettingsRow(title: "接管全部输出设备",
                        subtitle: "播放期间静音其他 App 的输出，从根源上防漏音",
                        badge: "实验",
                        metrics: metrics) {
                SettingsToggle(isOn: $state.blockOtherOutputs)
            }
            SettingsRowDivider(metrics: metrics)
            SettingsRow(title: "播放期间系统静音",
                        subtitle: "独占播放时静音系统声音，暂停后自动恢复",
                        metrics: metrics) {
                SettingsToggle(isOn: $state.muteSystemWhileRunning)
            }
            SettingsRowDivider(metrics: metrics)
            SettingsRow(title: "接管媒体键",
                        subtitle: "播放/暂停与上一首、下一首由净听响应",
                        metrics: metrics) {
                SettingsToggle(isOn: $state.mediaControlKeysEnabled)
            }
            if showsMediaKeyWarning {
                SettingsFootnote(metrics: metrics) { mediaKeyWarning }
            }
            SettingsRowDivider(metrics: metrics)
            SettingsRow(title: "系统音量联动",
                        subtitle: "系统音量键与滑块同步为净听音量",
                        metrics: metrics) {
                SettingsToggle(isOn: $state.systemVolumeMirror)
            }
        }
        .animation(DS.Motion.standard, value: showsMediaKeyWarning)
    }

    private var showsMediaKeyWarning: Bool {
        guard state.mediaControlKeysEnabled else { return false }
        return forceMediaKeyWarning || !MediaKeyTap.hasPermission()
    }

    private var mediaKeyWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("需在「系统设置 › 隐私与安全性 › 辅助功能」中勾选净听")
                .font(metrics.footnoteFont)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.xs)
            Button("去授权") { openAccessibilitySettings() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(DS.Palette.amber)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 哔哩哔哩

    private var biliSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "哔哩哔哩账号",
                                  detail: biliStateText,
                                  live: state.biliPhase == .loggedIn,
                                  metrics: metrics)
            SettingsBiliCard(metrics: metrics)
        }
    }

    private var biliStateText: String {
        switch state.biliPhase {
        case .loggedIn: return "已登录"
        case .qrWaiting, .qrScanned: return "扫码中"
        case .failed: return "登录失败"
        case .idle: return "未登录"
        }
    }

    // MARK: - 缓存

    private var cacheSection: some View {
        SettingsSection(title: "缓存", detail: state.cacheSizeText, metrics: metrics) {
            SettingsRow(title: "已下载歌曲",
                        subtitle: "清除后再次播放会重新下载无损音源",
                        metrics: metrics) {
                SettingsSmallButton(title: "清除", systemImage: "trash") {
                    state.clearCache()
                }
            }
        }
    }

    // MARK: - 网易云账号

    private var accountSection: some View {
        SettingsSection(title: "网易云账号",
                        detail: state.profile == nil ? "未登录" : "已登录",
                        live: state.profile != nil,
                        metrics: metrics) {
            HStack(spacing: metrics.controlSpacing) {
                profileAvatar
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    Text(state.profile?.nickname ?? "未登录")
                        .font(metrics.titleFont)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(accountSubtitle)
                        .font(metrics.subtitleFont)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer(minLength: DS.Space.m)
                if state.profile != nil {
                    SettingsDangerButton(title: "退出登录",
                                         systemImage: "rectangle.portrait.and.arrow.right") {
                        state.logout()
                    }
                }
            }
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .padding(.vertical, metrics.rowVerticalPadding)
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let profile = state.profile, !profile.avatarUrl.isEmpty {
            CoverArtwork(url: profile.avatarUrl, size: 32, radius: DS.Radius.artSmall,
                         borderOpacity: 0.14)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.artSmall, style: .continuous)
                    .fill(DS.Palette.surfaceSelected)
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .frame(width: 32, height: 32)
        }
    }

    private var accountSubtitle: String {
        guard let profile = state.profile else { return "扫码登录后即可拉取歌单" }
        return "UID \(profile.userId) · 歌单已同步"
    }

    // MARK: - 关于 / 退出

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("关于")
                    .font(metrics.headerFont)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .padding(.horizontal, DS.Space.xs)
                Text("净听以 hog mode 独占输出设备并自动切换采样率，绕过系统混音器消除 SRC；播放期间其他 App 的声音会被暂时屏蔽。")
                    .font(metrics.bodyFont)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsSection(title: "退出", metrics: metrics) {
                SettingsRow(title: "退出净听",
                            subtitle: "释放独占输出并关闭应用",
                            metrics: metrics) {
                    SettingsSmallButton(title: "退出", systemImage: "power") {
                        NSApp.terminate(nil)
                    }
                }
            }
            HStack(spacing: DS.Space.xs) {
                Spacer(minLength: 0)
                Text("Bit-perfect · 本地播放 · 无广告")
                    .font(DS.TypeScale.micro)
                    .tracking(DS.Tracking.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Palette.textQuaternary)
                Spacer(minLength: 0)
            }
        }
    }
}
