import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import PureListenCore

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            Text("净听")
                .font(.system(size: 20, weight: .semibold))
            Text("网易云音乐 · 无损独占输出")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch state.loginPhase {
            case .qrWaiting, .qrScanned:
                if let url = state.loginQRURL, let image = qrImage(from: url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 190, height: 190)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ProgressView().frame(width: 190, height: 190)
                }
                Text(state.loginPhase == .qrScanned ? "已在手机上确认, 正在登录…" : "打开网易云音乐 App 扫码登录")
                    .font(.callout)
                Text("登录后即可拉取歌单并以无损音质独占输出到耳机孔")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message).font(.callout).multilineTextAlignment(.center)
                HStack {
                    Button("重新扫码") { state.startLoginPolling() }
                    if state.hasMusicU {
                        Button("重试获取账号") { Task { await state.retryAccountOnly() } }
                    }
                }
            case .loggingIn:
                ProgressView().controlSize(.large)
                Text("登录成功, 正在获取用户信息…").font(.callout)
            case .idle, .loggedIn:
                ProgressView()
                Text("正在创建二维码…").font(.callout)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func qrImage(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

// MARK: - 主界面

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var showTracks = false
    @State private var showSettings = false
    @State private var showDetail = false
    @State private var homeTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showDetail {
                    Button { showDetail = false } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Text("正在播放").font(.headline)
                } else {
                    if showTracks || showSettings {
                        Button {
                            if showSettings { showSettings = false } else { showTracks = false }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                    }
                    Text(showSettings ? "设置"
                         : showTracks ? (state.currentPlaylist?.name ?? "歌单")
                         : "\(state.profile?.nickname ?? "") 的歌单")
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                if !showDetail {
                    Button {
                        showSettings = true
                        showTracks = false
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if showDetail {
                NowPlayingDetail()
            } else if showSettings {
                SettingsView()
            } else if showTracks {
                TrackListView()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        Picker("", selection: $homeTab) {
                            Text("我的歌单").tag(0)
                            Text("搜索").tag(1)
                            Text("B站收藏").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)
                        if homeTab == 0 {
                            QuickPlayBar()
                            PlaylistListView { playlist in
                                Task { await state.openPlaylist(playlist) }
                                showTracks = true
                            }
                        } else if homeTab == 1 {
                            SearchView { track in
                                state.play(index: state.appendTrack(track))
                            }
                        } else {
                            BiliFavoritesView()
                        }
                    }
                }
            }

            Divider()
            NowPlayingBar { showDetail = true }
        }
    }
}

// MARK: - 快捷播放(网易ID/链接 · B站 · 直链)

struct QuickPlayBar: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus").font(.caption).foregroundStyle(.secondary)
                TextField("网易云歌曲/ID · B站视频/BV号 · 音频直链", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { state.resolveAndPlay(input) }
                Button {
                    state.resolveAndPlay(input)
                } label: {
                    if state.quickPlayBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.circle.fill").font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .disabled(state.quickPlayBusy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error = state.quickPlayError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

struct PlaylistListView: View {
    @EnvironmentObject var state: AppState
    var onOpen: (NCPlaylist) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if state.playlists.isEmpty {
                    Text("还没有歌单").foregroundStyle(.secondary).padding(.top, 40)
                }
                ForEach(state.playlists) { playlist in
                    Button {
                        onOpen(playlist)
                    } label: {
                        HStack(spacing: 10) {
                            CoverImage(url: playlist.coverUrl, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name).font(.callout).lineLimit(1)
                                Text("\(playlist.trackCount) 首")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct TrackListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if state.tracks.isEmpty {
                    ProgressView().padding(.top, 40)
                }
                ForEach(Array(state.tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        state.play(index: index)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name)
                                    .font(.callout)
                                    .foregroundStyle(index == state.currentIndex ? Color.accentColor : .primary)
                                    .lineLimit(1)
                                Text(track.artists)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if track.vipOnly {
                                Text("VIP")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.2)))
                                    .foregroundStyle(.orange)
                            }
                            if index == state.currentIndex {
                                switch state.playerState {
                                case .playing:
                                    Image(systemName: "waveform")
                                        .foregroundStyle(Color.accentColor)
                                case .paused:
                                    Image(systemName: "pause.fill")
                                        .foregroundStyle(.secondary)
                                default:
                                    EmptyView()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - 底部播放条

struct NowPlayingBar: View {
    @EnvironmentObject var state: AppState
    var onOpenDetail: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { state.playPrevious() } label: { Image(systemName: "backward.fill") }
                    .buttonStyle(.plain)
                Button { state.playPause() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                Button { state.playNext() } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(.plain)
                Spacer()
                qualityBadge
            }
            if hasTrack {
                VStack(spacing: 2) {
                    Button { onOpenDetail?() } label: {
                        Text(state.trackStatus.title.isEmpty ? "未在播放" : state.trackStatus.title)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    Text(badgeText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.caption2)
                Slider(value: Binding(
                    get: { Double(state.volume) },
                    set: { state.setManualVolume(Float($0)) }
                ), in: 0...1)
                    .controlSize(.mini)
                if state.player.bitPerfect {
                    Text("位完美")
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var isPlaying: Bool {
        if case .playing = state.playerState { return true }
        return false
    }

    private var hasTrack: Bool {
        !state.trackStatus.title.isEmpty
    }

    private var qualityBadge: some View {
        Text(state.level == .hires ? "Hi-Res" : state.level == .lossless ? "无损" : "标准")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.16)))
    }

    private var badgeText: String {
        var parts: [String] = []
        if state.trackStatus.fileRate > 0 {
            let khz = String(format: "%.1f", Double(state.trackStatus.fileRate) / 1000)
            parts.append("\(khz)kHz/\(state.trackStatus.fileBits)bit")
        }
        parts.append(state.trackStatus.exclusive ? "独占输出" : "共享输出")
        if state.trackStatus.resampled { parts.append("已降至\(state.trackStatus.deviceRate / 1000)k") }
        if !state.trackStatus.format.isEmpty { parts.append(state.trackStatus.format.uppercased()) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("音质")
                        Picker("音质", selection: Binding(
                            get: { state.level },
                            set: { state.level = $0 }
                        )) {
                            ForEach([NCLevel.hires, .lossless, .exhigh, .standard], id: \.self) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        if state.level == .hires {
                            Text("内置 3.5mm 孔最高 96kHz, 192k 母带将自动降采样")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("输出设备")
                        Picker("输出设备", selection: Binding(
                            get: { state.autoDevice ? 0 : (state.selectedDevice?.id ?? 0) },
                            set: { newId in
                                if newId == 0 {
                                    state.autoDevice = true
                                } else if let device = state.devices.first(where: { $0.id == newId }) {
                                    state.selectDevice(device)
                                }
                            }
                        )) {
                            Text("自动(跟随耳机)").tag(0)
                            ForEach(state.devices) { device in
                                Text(device.name + (device.isBuiltIn ? " (内置)" : "")).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        settingLabel("启动时自动继续上次歌单")
                        Toggle("", isOn: Binding(
                            get: { state.autoResume },
                            set: { state.autoResume = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("接管全部输出设备(实验性, 默认关; 易在拔插时扰乱系统音频, 静音+音量键拦截已覆盖其作用)")
                        Toggle("", isOn: Binding(
                            get: { state.blockOtherOutputs },
                            set: { state.blockOtherOutputs = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("播放期间系统静音(第二道保险, 针对外接设备; 音量联动不受影响)")
                        Toggle("", isOn: Binding(
                            get: { state.muteSystemWhileRunning },
                            set: { state.muteSystemWhileRunning = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("接管媒体键(播放/暂停·上下曲; 播放中音量键改由本App软件调节, 根治扬声器爆音; 需辅助功能权限)")
                        Toggle("", isOn: Binding(
                            get: { state.mediaControlKeysEnabled },
                            set: { state.mediaControlKeysEnabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        if state.mediaControlKeysEnabled && !MediaKeyTap.hasPermission() {
                            Text("⚠ 需要在 系统设置 → 隐私与安全性 → 辅助功能 中勾选 净听")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("系统音量联动(音量键/设置滑块 → App 音量, 默认开)")
                        Toggle("", isOn: Binding(
                            get: { state.systemVolumeMirror },
                            set: { state.systemVolumeMirror = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(4)
                }

                
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("缓存 (\(state.cacheSizeText))")
                        Button("清除已下载歌曲缓存") { state.clearCache() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                    .padding(4)
                }

                BiliLoginSection()

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        settingLabel("账号 · \(state.profile?.nickname ?? "")")
                        Button("退出登录") { state.logout() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                    .padding(4)
                }

                Text("净听通过 hog mode 独占输出设备并自动切换采样率, 绕过 macOS 系统混音器, 消除 SRC。播放期间其他 App 的声音将被暂时屏蔽(与 iPhone 行为一致)。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Button {
                    NSApp.terminate(nil)   // applicationWillTerminate 会释放独占并恢复采样率
                } label: {
                    Label("退出净听", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(.red)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - 封面

/// 封面内存缓存(修复返回主界面时封面重复下载导致的卡顿)。
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 600 }

    func image(for url: String, size: Int) async -> NSImage? {
        let key = "\(url)#\(size)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard !url.isEmpty, var comps = URLComponents(string: url) else { return nil }
        comps.queryItems = [URLQueryItem(name: "param", value: "\(size)y\(size)")]
        guard let source = comps.url,
              let data = try? await URLSession.shared.data(from: source).0,
              let decoded = NSImage(data: data) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
}

struct CoverImage: View {
    let url: String
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.18))
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            if image == nil {
                image = await CoverCache.shared.image(for: url, size: Int(size) * 2)
            }
        }
    }
}

// MARK: - 播放详情页(含链路可视化)

struct NowPlayingDetail: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NowPlayingTabs()
    }
}

/// 播放链路实时可视化: 展示本 App 如何绕过系统混音器实现无 SRC 直通。
struct PipelineView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("播放链路 · 实时")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            stageRow(icon: "waveform", title: "音源",
                     detail: { Text(sourceLine) }, positive: state.trackStatus.fileRate > 0)
            connector(text: "FLAC/AAC 解码 · ExtAudioFile")
            stageRow(icon: "cpu", title: "解码",
                     detail: {
                         Text(state.trackStatus.resampled
                              ? "重采样 → \(state.trackStatus.deviceRate / 1000)kHz"
                              : "位完美直通 · 无重采样")
                     },
                     positive: !state.trackStatus.resampled)
            connector(text: "无锁环形缓冲 · SPSC")
            stageRow(icon: "gauge.with.dots.needle.50percent", title: "缓冲",
                     detail: { bufferLine }, positive: true)
            connector(text: "IOProc 直写 · 绕过 coreaudiod 混音器")
            stageRow(icon: state.trackStatus.exclusive ? "lock.fill" : "lock.open",
                     title: "独占输出",
                     detail: {
                         Text(state.trackStatus.exclusive
                              ? "hog mode ✓ 已独占设备" : "未独占(共享模式)")
                     },
                     positive: state.trackStatus.exclusive)
            connector(text: "采样率自动匹配")
            stageRow(icon: "headphones", title: state.selectedDevice?.name ?? "输出设备",
                     detail: { Text(rateLine) }, positive: true)

            // SRC 消除总结
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(state.trackStatus.resampled ? "SRC: 音源超出设备能力, 已高质量降采样"
                     + (state.player.bitPerfect ? "" : "")
                     : "SRC 已消除 · 系统混音器已绕过")
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                if state.player.bitPerfect {
                    Text("位完美 ✓").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("数字衰减中").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private var sourceLine: String {
        let t = state.trackStatus
        guard t.fileRate > 0 else { return "—" }
        return String(format: "%@ · %.1fkHz/%dbit", t.format.uppercased(),
                      Double(t.fileRate) / 1000, t.fileBits)
    }

    private var bufferLine: some View {
        TimelineStatsText()
    }

    private var rateLine: String {
        let t = state.trackStatus
        guard t.deviceRate > 0 else { return "—" }
        let match = t.deviceRate == t.fileRate ? "与音源一致" : "≠ 音源(\(t.fileRate / 1000)k)"
        return String(format: "%dkHz · %@", t.deviceRate / 1000, match)
    }

    private func stageRow<Detail: View>(icon: String, title: String, @ViewBuilder detail: () -> Detail, positive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(positive ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold))
                detail().font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func connector(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
            Text(text).font(.system(size: 8)).foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

/// 用 TimelineView 周期读取环形缓冲实时填充率。
struct TimelineStatsText: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let stats = state.player.ringStats()
            let percent = stats.capacity > 0 ? Double(stats.available) / Double(stats.capacity) : 0
            let seconds = Double(stats.available) / max(Double(state.trackStatus.deviceRate), 1)
            HStack(spacing: 6) {
                ProgressView(value: percent)
                    .frame(width: 60)
                Text(String(format: "%.0f%% · %.2fs 缓冲", percent * 100, seconds))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
