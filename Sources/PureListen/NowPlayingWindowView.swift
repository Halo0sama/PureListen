import SwiftUI
import CoreImage.CIFilterBuiltins
import PureListenCore

// MARK: - 共享二维码视图

struct QRCodeView: View {
    let content: String
    var size: CGFloat = 190

    var body: some View {
        if let image = qrImage {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ProgressView().frame(width: size, height: size)
        }
    }

    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

// MARK: - 独立播放详情窗口(播放 / 歌词 / 链路)

struct NowPlayingTabs: View {
    @EnvironmentObject var state: AppState
    @State private var tab = 0
    @State private var draggingPosition: Double?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Image(systemName: "play.circle").tag(0)
                Image(systemName: "text.quote").tag(1)
                Image(systemName: "waveform.path").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Divider().padding(.top, 8)

            switch tab {
            case 1: LyricsPage()
            case 2: ScrollView { PipelineView().padding(16) }
            default: PlayerPage(draggingPosition: $draggingPosition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(coverGradient)
        .onAppear { dominant = coverDominantColor(state.currentCoverURL) }
        .onChange(of: state.currentCoverURL) { newValue in
            dominant = coverDominantColor(newValue)
        }
    }

    /// 封面主色调渐变背景(NeriPlayer 式沉浸感)。
    private var coverGradient: some View {
        ZStack {
            Rectangle().fill(.background)
            LinearGradient(
                colors: [dominant.opacity(0.32), dominant.opacity(0.05), .clear],
                startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    @State private var dominant: Color = .accentColor

    private struct PlayerPage: View {
        @EnvironmentObject var state: AppState
        @Binding var draggingPosition: Double?
        @State private var dominant: Color = .accentColor

        var body: some View {
            VStack(spacing: 16) {
                Spacer(minLength: 8)
                // 大封面
                CoverImage(url: state.currentCoverURL, size: 210)
                    .shadow(color: dominant.opacity(0.45), radius: 28, y: 14)
                    .onAppear { dominant = coverDominantColor(state.currentCoverURL) }
                    .onChange(of: state.currentCoverURL) { dominant = coverDominantColor($0) }

                VStack(spacing: 4) {
                    Text(state.trackStatus.title.isEmpty ? "未在播放" : state.trackStatus.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(state.trackStatus.artist.isEmpty ? "—" : state.trackStatus.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(state.currentSourceLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(dominant.opacity(0.2)))
                        Text(badges)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                // 进度
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { draggingPosition ?? state.trackStatus.positionSeconds },
                            set: { draggingPosition = $0 }),
                        in: 0...max(state.trackStatus.seconds, 1)
                    ) { editing in
                        if !editing, let target = draggingPosition {
                            state.seek(to: target)
                            draggingPosition = nil
                        }
                    }
                    HStack {
                        Text(fmt(draggingPosition ?? state.trackStatus.positionSeconds)).font(.caption2)
                            .monospacedDigit()
                        Spacer()
                        Text("-" + fmt(max(state.trackStatus.seconds -
                            (draggingPosition ?? state.trackStatus.positionSeconds), 0)))
                            .font(.caption2).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }

                // 控制
                HStack(spacing: 28) {
                    Button { state.playPrevious() } label: {
                        Image(systemName: "backward.fill").font(.title2)
                    }.buttonStyle(.plain)
                    Button { state.playPause() } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }.buttonStyle(.plain)
                    Button { state.playNext() } label: {
                        Image(systemName: "forward.fill").font(.title2)
                    }.buttonStyle(.plain)
                }
                .foregroundStyle(dominant)

                // 音量 + 联动指示
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.caption)
                    Slider(value: Binding(
                        get: { Double(state.volume) },
                        set: { state.setManualVolume(Float($0)) }
                    ), in: 0...1).controlSize(.regular)
                    if state.player.bitPerfect {
                        Text("位完美").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: 320)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 24)
        }

        private var isPlaying: Bool {
            if case .playing = state.playerState { return true }
            return false
        }

        private var badges: String {
            let t = state.trackStatus
            guard t.fileRate > 0 else { return "" }
            return String(format: "%.1fkHz/%dbit · %@ · %@",
                          Double(t.fileRate) / 1000, t.fileBits,
                          t.format.uppercased(),
                          t.exclusive ? "独占" : "共享")
        }

        private func fmt(_ s: Double) -> String {
            String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
        }
    }

    private struct LyricsPage: View {
        @EnvironmentObject var state: AppState

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if state.lyrics.isEmpty {
                            Text("暂无歌词\n(非网易云歌曲或该曲无歌词)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                                .multilineTextAlignment(.center)
                        }
                        ForEach(Array(state.lyrics.enumerated()), id: \.element.id) { pair in
                            LyricRowView(line: pair.element, active: pair.offset == state.lyricIndex) {
                                state.seek(to: max(pair.element.time - 0.2, 0))
                            }
                            .id(pair.element.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: state.lyricIndex) { newIndex in
                    if newIndex >= 0, newIndex < state.lyrics.count {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(state.lyrics[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}


/// 取封面主色调(1px CIAreaAverage)。
func coverDominantColor(_ urlString: String) -> Color {
    guard !urlString.isEmpty,
          let source = URL(string: urlString + "?param=60y60"),
          let data = try? Data(contentsOf: source),
          let image = NSImage(data: data),
          let tiff = image.tiffRepresentation,
          let cg = NSBitmapImageRep(data: tiff)?.cgImage else { return .accentColor }
    let ci = CIImage(cgImage: cg)
    let filter = CIFilter(name: "CIAreaAverage", parameters: [
        kCIInputImageKey: ci,
        kCIInputExtentKey: CIVector(cgRect: ci.extent),
    ])
    guard let output = filter?.outputImage else { return .accentColor }
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
    return Color(red: Double(pixel[0]) / 255,
                 green: Double(pixel[1]) / 255,
                 blue: Double(pixel[2]) / 255)
}

// MARK: - 搜索页

struct SearchView: View {
    @EnvironmentObject var state: AppState
    var onPlay: (NCTrack) -> Void
    @State private var submitted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("搜索歌曲 / 歌手", text: $state.searchKeyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        state.doSearch()
                        submitted = true
                    }
                Button {
                    state.doSearch()
                    submitted = true
                } label: {
                    if state.searchBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.right.circle.fill").font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .disabled(state.searchBusy)
            }
            .padding(.horizontal, 14)

            if submitted {
                VStack(spacing: 2) {
                    if state.searchResults.isEmpty && !state.searchBusy {
                        Text("无结果").font(.caption).foregroundStyle(.secondary).padding(.top, 20)
                    }
                    ForEach(state.searchResults) { track in
                        Button { onPlay(track) } label: {
                            HStack(spacing: 8) {
                                CoverImage(url: track.coverURL, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name).font(.callout).lineLimit(1)
                                    Text(track.artists).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if track.vipOnly {
                                    Text("VIP").font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4).padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.2)))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - B站登录(设置页内嵌)

struct BiliLoginSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                settingLabel("哔哩哔哩账号")
                switch state.biliPhase {
                case .loggedIn:
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(state.biliUname.isEmpty ? "已登录" : state.biliUname).font(.callout)
                        Spacer()
                        Button("退出") { state.logoutBili() }.buttonStyle(.link).font(.callout)
                    }
                case .qrWaiting, .qrScanned:
                    VStack(spacing: 8) {
                        if let url = state.biliQRURL {
                            QRCodeView(content: url, size: 160)
                        }
                        Text(state.biliPhase == .qrScanned ? "已扫码, 请在手机上确认" : "用哔哩哔哩 App 扫码登录")
                            .font(.caption)
                        Button {
                            state.cancelBiliLogin()
                        } label: {
                            Label("返回其他登录方式", systemImage: "chevron.left")
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.orange)
                    HStack(spacing: 14) {
                        Button("改用网页登录") { state.onOpenBiliWebLogin?() }.buttonStyle(.link)
                        Button("重试扫码") { state.startBiliLogin() }.buttonStyle(.link)
                    }
                case .idle:
                    HStack(spacing: 14) {
                        Button("网页登录(推荐)") { state.onOpenBiliWebLogin?() }
                            .buttonStyle(.link).font(.callout)
                        Button("扫码登录") { state.startBiliLogin() }
                            .buttonStyle(.link).font(.callout)
                    }
                }
                Text("登录后 B 站播放可获取更高音质音频流")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}


// MARK: - B站收藏

struct BiliFavoritesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            if state.biliPhase != .loggedIn {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("未登录哔哩哔哩").font(.callout)
                    Text("在 设置 → 哔哩哔哩账号 里扫码登录后\n即可浏览并播放你的收藏")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
            } else if let folder = state.currentFavFolder {
                // 收藏夹内视频列表
                VStack(spacing: 4) {
                    HStack {
                        Button {
                            state.currentFavFolder = nil
                            state.favVideos = []
                        } label: {
                            Label("返回收藏夹", systemImage: "chevron.left")
                        }
                        .buttonStyle(.link).font(.caption)
                        Spacer()
                        Text("\(folder.title) · \(state.favVideos.count)条")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(state.favVideos) { video in
                                Button {
                                    state.playBiliVideo(video)
                                } label: {
                                    HStack(spacing: 10) {
                                        CoverImage(url: video.cover, size: 46)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(video.title)
                                                .font(.callout)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text("\(video.upper) · \(video.durationSeconds / 60):\(String(format: "%02d", video.durationSeconds % 60))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            if state.favHasMore {
                                Button {
                                    Task { await state.loadMoreFavs() }
                                } label: {
                                    if state.favBusy {
                                        ProgressView().controlSize(.small).padding(.vertical, 8)
                                    } else {
                                        Text("加载更多")
                                            .font(.caption)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                }
                                .buttonStyle(.borderless)
                            } else if state.favVideos.isEmpty && !state.favBusy {
                                Text("收藏夹是空的").font(.caption).foregroundStyle(.secondary)
                                    .padding(.top, 30)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                // 收藏夹列表
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if state.favFolders.isEmpty {
                            if state.favBusy {
                                ProgressView().padding(.top, 40)
                            } else {
                                Text("没有收藏夹").font(.caption).foregroundStyle(.secondary)
                                    .padding(.top, 40)
                            }
                        }
                        ForEach(state.favFolders) { folder in
                            Button {
                                Task { await state.openFavFolder(folder) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.title).font(.callout).lineLimit(1)
                                        Text("\(folder.mediaCount) 个视频")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .task {
                    if state.favFolders.isEmpty {
                        await state.loadFavFolders()
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}


/// 单行歌词(原文+翻译, 可点击跳转)。
struct LyricRowView: View {
    let line: AppState.LyricLine
    let active: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.text)
                .font(.system(size: 16, weight: active ? .bold : .regular))
                .foregroundStyle(active ? Color.primary : Color.secondary)
            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
