import SwiftUI
import PureListenCore

// MARK: - 首页(歌单 / 搜索 / B站)

struct PopoverHome: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter

    /// 已经创建过的页面。页面创建一次后保留，切换分段只做显示/隐藏，
    /// 避免每次点击 B 站都重新构建整页（会卡一下）。
    @State private var loadedTabs: Set<PopoverTab> = [.playlists]

    var body: some View {
        VStack(spacing: DS.Space.m) {
            DSSegmented(items: PopoverTab.allCases, title: { $0.title },
                        selection: $router.tab,
                        onHover: { item in
                            // 悬停到 B 站时提前把页面构建好，点击时就不会有首帧卡顿。
                            if let item { loadedTabs.insert(item) }
                        })
                .padding(.horizontal, DS.Space.popoverPadding)

            ZStack {
                PlaylistPane()
                    .opacity(router.tab == .playlists ? 1 : 0)
                    .allowsHitTesting(router.tab == .playlists)
                    .accessibilityHidden(router.tab != .playlists)

                if loadedTabs.contains(.bilibili) {
                    BiliPane()
                        .opacity(router.tab == .bilibili ? 1 : 0)
                        .allowsHitTesting(router.tab == .bilibili)
                        .accessibilityHidden(router.tab != .bilibili)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: router.tab) { _, tab in
                // 兜底：没有经过 hover 的切换路径也能保证页面已创建。
                loadedTabs.insert(tab)
            }
            .onAppear {
                // 预览/深链可能直接以 B 站作为初始分段。
                loadedTabs.insert(router.tab)
            }
        }
        .padding(.top, DS.Space.xs)
    }
}

// MARK: - 歌单

private struct PlaylistPane: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter

    var body: some View {
        VStack(spacing: DS.Space.m) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    if state.playlists.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 60)
                    }
                    ForEach(state.playlists) { playlist in
                        DSListRow(title: playlist.name,
                                  subtitle: "\(playlist.trackCount) 首",
                                  height: 46) {
                            Task { await state.openPlaylist(playlist) }
                            router.openPlaylist()
                        } leading: {
                            CoverArtwork(url: playlist.coverUrl, size: 34,
                                         radius: DS.Radius.artSmall, shadow: true,
                                         borderOpacity: 0.14)
                        } trailing: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DS.Palette.textQuaternary)
                        }
                        .padding(.horizontal, DS.Space.s)
                    }
                }
                .padding(.bottom, 4)
            }
            .contentMargins(.bottom, 132, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .padding(.horizontal, DS.Space.popoverPadding - DS.Space.s)
    }
}

// MARK: - B站

private struct BiliPane: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.biliPhase != .loggedIn {
                notLoggedIn
            } else if let folder = state.currentFavFolder {
                videos(folder)
            } else {
                folders
            }
        }
        .padding(.horizontal, DS.Space.popoverPadding)
    }

    private var notLoggedIn: some View {
        VStack(spacing: DS.Space.l) {
            Spacer(minLength: 0)
            Image(systemName: "play.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(hex: 0xFB7299))
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 4) {
                Text("还没有登录哔哩哔哩")
                    .font(DS.TypeScale.body)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("登录后可直接播放收藏夹音频, 自动取最高码率")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: DS.Space.s) {
                DSPillButton(title: "网页登录(推荐)", systemImage: "safari", prominent: true) {
                    state.onOpenBiliWebLogin?()
                }
                DSPillButton(title: "扫码登录") {
                    state.startBiliLogin()
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var folders: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if state.favBusy && state.favFolders.isEmpty {
                    ProgressView().controlSize(.small).padding(.top, 50)
                }
                ForEach(state.favFolders) { folder in
                    DSListRow(title: folder.title,
                              subtitle: "\(folder.mediaCount) 个视频", height: 44) {
                        Task { await state.openFavFolder(folder) }
                    } leading: {
                        DSGlyphTile(systemName: "folder.fill", tint: Color(hex: 0xFB7299), size: 28)
                    } trailing: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Palette.textQuaternary)
                    }
                }
            }
        }
        .contentMargins(.bottom, 132, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task {
            if state.favFolders.isEmpty { await state.loadFavFolders() }
        }
    }

    private func videos(_ folder: BiliClient.FavFolder) -> some View {
        VStack(spacing: DS.Space.s) {
            HStack {
                DSIconButton(systemName: "chevron.left", size: 22, iconSize: 10, help: "返回") {
                    state.currentFavFolder = nil
                    state.favVideos = []
                }
                Text(folder.title)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(state.favVideos.count) 条")
                    .font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.favVideos) { video in
                        BiliVideoRow(video: video)
                    }
                    if state.favHasMore {
                        Button {
                            Task { await state.loadMoreFavs() }
                        } label: {
                            if state.favBusy {
                                ProgressView().controlSize(.small).padding(.vertical, 8)
                            } else {
                                Text("加载更多")
                                    .font(DS.TypeScale.caption)
                                    .foregroundStyle(.tint)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.bottom, 132, for: .scrollContent)
        }
    }
}

private struct BiliVideoRow: View {
    @EnvironmentObject var state: AppState
    let video: BiliClient.FavVideo

    var body: some View {
        DSListRow(title: video.title, subtitle: subtitleText, height: 54) {
            state.playBiliVideo(video)
        } leading: {
            CoverArtwork(url: video.cover, size: 44, radius: DS.Radius.artSmall,
                         shadow: true, borderOpacity: 0.12)
        } trailing: {
            Image(systemName: "play.circle")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    private var subtitleText: String {
        let seconds = video.durationSeconds
        return "\(video.upper) · \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

// MARK: - 歌单内页

struct PopoverTrackList: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                header
                    .padding(.bottom, DS.Space.s)
                if state.tracks.isEmpty {
                    ProgressView().controlSize(.small).padding(.top, 40)
                }
                ForEach(Array(state.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, index: index)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, DS.Space.popoverPadding - 6)
        }
        .contentMargins(.bottom, 132, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private var header: some View {
        if let playlist = state.currentPlaylist {
            HStack(spacing: DS.Space.l) {
                CoverArtwork(url: playlist.coverUrl, size: 58, radius: DS.Radius.art,
                             shadow: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(DS.Tracking.tight)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(2)
                    Text("\(playlist.trackCount) 首 · 网易云歌单")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                DSIconButton(systemName: "play.fill", size: 30, iconSize: 12, isActive: true,
                             help: "全部播放") {
                    state.play(index: 0)
                }
            }
            .padding(DS.Space.l)
            .dsSurface(DS.Radius.card)
        }
    }
}

private struct TrackRow: View {
    @EnvironmentObject var state: AppState
    let track: NCTrack
    let index: Int

    private var isCurrent: Bool { index == state.currentIndex }

    @Environment(\.albumTint) private var tint

    var body: some View {
        DSListRow(title: track.name, subtitle: track.artists,
                  isSelected: isCurrent, height: 44) {
            state.play(index: index)
        } leading: {
            CoverArtwork(url: track.coverURL, size: 32, radius: DS.Radius.artSmall,
                         borderOpacity: 0.10)
                .frame(width: 32, height: 32)
        } trailing: {
            HStack(spacing: DS.Space.s) {
                if track.vipOnly {
                    DSChip(text: "VIP", tone: .neutral, compact: true)
                }
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                } else {
                    Text(durationText)
                        .font(DS.TypeScale.timecode)
                        .foregroundStyle(DS.Palette.textSecondary.opacity(0.8))
                }
            }
        }
    }

    private var isPlaying: Bool {
        if case .playing = state.playerState { return isCurrent }
        return false
    }

    private var durationText: String {
        let seconds = track.durationMs / 1000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
