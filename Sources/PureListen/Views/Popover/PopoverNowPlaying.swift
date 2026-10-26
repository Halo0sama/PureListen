import SwiftUI
import PureListenCore

// MARK: - Popover 内的「正在播放」

/// 菜单栏面板内的播放、歌词与链路，所有页面均留在小播放器中。
enum NowPlayingPane: Hashable, CaseIterable {
    case player, lyrics, signal

    var title: String {
        switch self {
        case .player: return "播放"
        case .lyrics: return "歌词"
        case .signal: return "链路"
        }
    }
}

struct PopoverNowPlayingPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter

    @State private var scrubbing: Double?
    @Environment(\.albumTint) private var tint

    var body: some View {
        VStack(spacing: DS.Space.m) {
            DSSegmented(items: NowPlayingPane.allCases,
                        title: { $0.title },
                        selection: $router.nowPlayingPane)
                .frame(width: 222)

            ZStack {
                if router.nowPlayingPane == .signal {
                    PlaybackSignalView(compact: true).transition(.opacity)
                } else if !hasTrack {
                    idle
                } else if router.nowPlayingPane == .player {
                    playerPane.transition(.opacity)
                } else {
                    LyricsPane(lines: state.lyrics,
                               activeIndex: state.lyricIndex,
                               onSeek: { state.seek(to: $0) }).transition(.opacity)
                }
            }
            .animation(DS.Motion.page, value: router.nowPlayingPane)
        }
        .padding(.horizontal, 22)
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.l)
    }

    private var hasTrack: Bool { !state.trackStatus.title.isEmpty }

    // MARK: 播放页

    private var playerPane: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CoverArtwork(url: state.currentCoverURL, size: 216,
                         radius: DS.Radius.artHero, shadow: true,
                         borderOpacity: 0.16)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.artHero, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                }

            VStack(spacing: 3) {
                Text(state.trackStatus.title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(state.trackStatus.artist.isEmpty ? "—" : state.trackStatus.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.top, 14)

            chips
                .padding(.top, 7)

            seek
                .padding(.top, 16)

            controls
                .padding(.top, 14)

            PlaybackControlStatus()

            DSVolumeBar(volume: Double(state.volume), tint: tint) { value in
                state.setManualVolume(Float(value))
            }
            .frame(maxWidth: 230)
            .padding(.top, 16)

            if let next = nextTrackLine {
                Text("接下来  \(next)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 14)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// 下一首提示（仅网易云歌单队列；B站/直链队列不显示）。
    private var nextTrackLine: String? {
        guard state.currentItem == nil else { return nil }
        let next = state.currentIndex + 1
        guard state.tracks.indices.contains(next) else { return nil }
        let track = state.tracks[next]
        return track.artists.isEmpty ? track.name : "\(track.name) · \(track.artists)"
    }

    private var chips: some View {
        HStack(spacing: 5) {
            DSChip(text: levelShort, tone: .neutral, compact: true)
            if state.trackStatus.fileRate > 0 {
                DSChip(text: WindowFormatting.rate(state.trackStatus.fileRate), tone: .neutral, compact: true)
            }
            if state.trackStatus.fileBits > 0 {
                DSChip(text: "\(state.trackStatus.fileBits) bit", tone: .neutral, compact: true)
            }
            if !state.trackStatus.format.isEmpty {
                DSChip(text: state.trackStatus.format.uppercased(), tone: .neutral, compact: true)
            }
            if state.player.bitPerfect {
                DSChip(text: "位完美", systemImage: "checkmark.seal.fill", tone: .mint,
                       compact: true)
            }
        }
    }

    private var seek: some View {
        let total = max(state.trackStatus.seconds, 0)
        let position = scrubbing.map { $0 * total } ?? state.trackStatus.positionSeconds
        let fraction = total > 0 ? min(max(position / total, 0), 1) : 0
        return VStack(spacing: 3) {
            DSSeekBar(progress: fraction, tint: tint, height: 4,
                      onScrub: { value in
                          state.seek(to: value * total)
                          scrubbing = nil
                      },
                      onScrubbing: { scrubbing = $0 })
                .disabled(total <= 0)
            HStack {
                Text(format(position)).font(DS.TypeScale.timecode)
                Spacer()
                Text("-" + format(max(total - position, 0))).font(DS.TypeScale.timecode)
            }
            .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            DSIconButton(systemName: "backward.fill", size: 32, iconSize: 14,
                         help: "上一首") { state.playPrevious() }
            DSPlayButton(isPlaying: isPlaying, size: 46) { state.playPause() }
            DSIconButton(systemName: "forward.fill", size: 32, iconSize: 14,
                         help: "下一首") { state.playNext() }
        }
    }

    // MARK: 无曲目

    private var idle: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer()
            ZStack {
                Circle().fill(DS.Palette.surfaceSelected).frame(width: 108, height: 108)
                DSBrandMark(size: 40, tint: DS.Palette.textSecondary)
            }
            VStack(spacing: 4) {
                Text("还没有在播放")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("从歌单里挑一首, 或去搜索")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            DSPillButton(title: "浏览歌单", systemImage: "square.stack", prominent: true) {
                router.home()
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: 辅助

    private var isPlaying: Bool {
        if case .playing = state.playerState { return true }
        return false
    }

    private var levelShort: String {
        WindowFormatting.levelShort(state.trackStatus.level, fallback: state.level)
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 歌词

private struct LyricsPane: View {
    var lines: [AppState.LyricLine]
    var activeIndex: Int
    var onSeek: (Double) -> Void

    var body: some View {
        if lines.isEmpty {
            VStack {
                Spacer()
                DSEmptyState(systemImage: "text.quote",
                             title: "暂无歌词",
                             message: "这首歌没有可用的歌词, 或来自非网易云来源")
                Spacer()
                Spacer()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { pair in
                            LyricLineRow(line: pair.element,
                                         active: pair.offset == activeIndex) {
                                onSeek(max(pair.element.time - 0.2, 0))
                            }
                            .id(pair.element.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 60)
                }
                .scrollIndicators(.never)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.14),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .onAppear {
                    guard lines.indices.contains(activeIndex) else { return }
                    proxy.scrollTo(lines[activeIndex].id, anchor: .center)
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard lines.indices.contains(newValue) else { return }
                    withAnimation(.smooth(duration: 0.35)) {
                        proxy.scrollTo(lines[newValue].id, anchor: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LyricLineRow: View {
    let line: AppState.LyricLine
    let active: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.text)
                .font(.system(size: active ? 16 : 13.5,
                              weight: active ? .semibold : .regular))
                .foregroundStyle(active ? DS.Palette.textPrimary
                                        : DS.Palette.textSecondary.opacity(0.62))
                .lineSpacing(1.5)
            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(.system(size: 10.5))
                    .foregroundStyle(active ? DS.Palette.textSecondary
                                            : DS.Palette.textTertiary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(DS.Motion.quick, value: active)
    }
}
