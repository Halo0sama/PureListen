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
                    accountsSection.id("settings-account")
                    qualitySection.id("settings-quality")
                    networkSection.id("settings-network")
                    outputSection.id("settings-output")
                    protectionSection.id("settings-protection")
                    cacheSection.id("settings-cache")
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
            .dsScrollFade(top: 24, bottom: layout == .window ? 24 : 0)
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
                        metrics: metrics) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("网易云").font(metrics.subtitleFont).foregroundStyle(DS.Palette.textSecondary)
                DSSegmented(items: Self.qualityOrder,
                            title: shortQualityTitle,
                            selection: qualityBinding,
                            height: metrics.segmentedHeight)
                Text("哔哩哔哩").font(metrics.subtitleFont).foregroundStyle(DS.Palette.textSecondary)
                    .padding(.top, 6)
                DSSegmented(items: BiliAudioQuality.allCases,
                            title: { $0.label }, selection: $state.biliQuality,
                            height: metrics.segmentedHeight)
                Text("新播放生效；Hi-Res 需音源及账号支持。")
                    .font(metrics.subtitleFont).foregroundStyle(DS.Palette.textSecondary)

            }
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, metrics.rowVerticalPadding)
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

    private var networkSection: some View {
        SettingsSection(title: "网络", metrics: metrics) {
            SettingsRow(title: "连接方式", metrics: metrics) {
                Picker("连接方式", selection: $state.networkMode) {
                    ForEach(NetworkMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
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
                        metrics: metrics) {
                SettingsToggle(isOn: $state.autoResume)
            }
        }
    }

    private var deviceSubtitle: String {
        if state.autoDevice { return "优先外置输出；切换后暂停，点击播放继续" }
        guard let device = state.selectedDevice else { return "指定设备离线，连接后点击播放" }
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
                        metrics: metrics) {
                SettingsToggle(isOn: $state.mediaControlKeysEnabled)
            }
            if showsMediaKeyWarning {
                SettingsFootnote(metrics: metrics) { mediaKeyWarning }
            }
            SettingsRowDivider(metrics: metrics)
            SettingsRow(title: "系统音量联动",
                        subtitle: "同一设备上的调节同步；插拔后音量最多 10%",
                        metrics: metrics) {
                SettingsToggle(isOn: $state.systemVolumeMirror)
            }
        }
        .animation(DS.Motion.standard, value: showsMediaKeyWarning)
    }

    private var showsMediaKeyWarning: Bool {
        guard state.mediaControlKeysEnabled || state.systemVolumeMirror else { return false }
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

    // MARK: - 缓存

    private var cacheSection: some View {
        SettingsSection(title: "缓存", detail: state.cacheSizeText, metrics: metrics) {
            SettingsRow(title: "已下载歌曲",
                        metrics: metrics) {
                SettingsSmallButton(title: "清除", systemImage: "trash") {
                    state.clearCache()
                }
            }
        }
    }

    private var accountsSection: some View {
        SettingsSection(title: "账号", metrics: metrics) {
            SettingsAccountRow(avatarURL: state.profile?.avatarUrl ?? "",
                               name: state.profile?.nickname ?? "未登录",
                               service: "网易云", metrics: metrics) {
                if state.profile != nil {
                    SettingsDangerButton(title: "退出登录", systemImage: "rectangle.portrait.and.arrow.right") {
                        state.logout()
                    }
                }
            }
            SettingsRowDivider(metrics: metrics)
            SettingsBiliCard(metrics: metrics).id("settings-bili")
        }
    }

    // MARK: - 关于 / 退出

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            SettingsSection(title: "退出", metrics: metrics) {
                SettingsRow(title: "退出净听",
                            metrics: metrics) {
                    SettingsSmallButton(title: "退出", systemImage: "power") {
                        NSApp.terminate(nil)
                    }
                }
            }

        }
    }
}
