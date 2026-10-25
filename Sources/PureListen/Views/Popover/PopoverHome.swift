import SwiftUI
import PureListenCore

// MARK: - 首页(歌单 / 搜索 / B站)

struct PopoverHome: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter

    var body: some View {
        VStack(spacing: DS.Space.m) {
            DSSegmented(items: PopoverTab.allCases, title: { $0.title },
                        selection: $router.tab)
                .padding(.horizontal, DS.Space.popoverPadding)

            Group {
                switch router.tab {
                case .playlists:
                    PlaylistPane()
                case .search:
                    SearchPane()
                case .bilibili:
                    BiliPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, DS.Space.xs)
    }
}

// MARK: - 歌单

private struct PlaylistPane: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter
    @State private var quickInput = ""

    var body: some View {
        VStack(spacing: DS.Space.m) {
            QuickPlayField()

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

/// 快捷播放: 粘贴网易云 / B站 / 直链。
private struct QuickPlayField: View {
    @EnvironmentObject var state: AppState
    @Environment(\.albumTint) private var tint
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(focused ? tint : DS.Palette.textTertiary)
                TextField("粘贴网易云 / B站 / 音频直链", text: $input)
                    .textFieldStyle(.plain)
                    .font(DS.TypeScale.body)
                    .focused($focused)
                    .focusEffectDisabled()
                    .onSubmit(submit)
                if state.quickPlayBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                } else if !input.isEmpty {
                    Button(action: submit) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 19, height: 19)
                            .background(Circle().fill(tint))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
                    .fill(DS.Palette.surfaceHover.opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
                            .strokeBorder(focused ? tint.opacity(0.55) : DS.Palette.hairline,
                                          lineWidth: focused ? 1.2 : 1)
                    }
            }
            .animation(DS.Motion.quick, value: focused)

            if let error = state.quickPlayError {
                Text(error)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.rose)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, DS.Space.l)
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        state.resolveAndPlay(value)
        input = ""
    }
}

// MARK: - 搜索

private struct SearchPane: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DS.Space.m) {
            DSSearchField(placeholder: "搜索歌曲 / 歌手", text: $state.searchKeyword,
                          isBusy: state.searchBusy) {
                state.doSearch()
            }
            .padding(.horizontal, DS.Space.l)

            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    if state.searchResults.isEmpty {
                        if state.searchBusy {
                            ProgressView().controlSize(.small).padding(.top, 60)
                        } else {
                            DSEmptyState(systemImage: "magnifyingglass",
                                         title: "搜索网易云曲库",
                                         message: "输入歌名或歌手, 回车开始搜索")
                                .padding(.top, 30)
                        }
                    }
                    ForEach(state.searchResults) { track in
                        SearchResultRow(track: track)
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

private struct SearchResultRow: View {
    @EnvironmentObject var state: AppState
    let track: NCTrack

    var body: some View {
        DSListRow(title: track.name, subtitle: track.artists, height: 46) {
            let index = state.appendTrack(track)
            state.play(index: index)
        } leading: {
            CoverArtwork(url: track.coverURL, size: 34, radius: DS.Radius.artSmall,
                         shadow: true, borderOpacity: 0.12)
        } trailing: {
            if track.vipOnly {
                DSChip(text: "VIP", tone: .neutral, compact: true)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Palette.textQuaternary)
            }
        }
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
