import SwiftUI
import PureListenCore

// MARK: - 「正在播放」页

/// 主窗口的封面页: 大封面 + 曲目信息 + 徽标 + 进度 + 播放控制 + 音量。
///
/// 版面在 940×640 下留足呼吸; 窗口缩到最小 820×560 时自动切换紧凑排版。
struct WindowHeroPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.albumTint) private var tint
    @Environment(\.dsIsDark) private var isDark

    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 0) {
            WindowPageToolbar(title: "正在播放",
                              detail: hasTrack ? state.currentSourceLabel : nil)
            GeometryReader { geo in
                let compact = geo.size.height < 545
                VStack(spacing: 0) {
                    Spacer(minLength: compact ? 6 : 14)
                    if hasTrack {
                        playingContent(art: artSize(for: geo.size),
                                       width: geo.size.width,
                                       compact: compact)
                    } else {
                        idleContent(compact: compact)
                    }
                    Spacer(minLength: compact ? 6 : 18)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: 数据

    private var hasTrack: Bool { !state.trackStatus.title.isEmpty }

    private var isPlaying: Bool {
        if case .playing = state.playerState { return true }
        return false
    }

    private var artistLine: String {
        let artist = state.trackStatus.artist
        if artist.isEmpty { return state.currentSourceLabel }
        return artist
    }

    private var levelLabel: String {
        WindowFormatting.levelShort(state.trackStatus.level, fallback: state.level)
    }

    private var formatText: String {
        state.trackStatus.format.uppercased()
    }

    /// 封面尺寸随窗口收缩, 但保持在 260…300 的观感区间内。
    private func artSize(for size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.37
        let byHeight = size.height * 0.50
        let base = min(max(min(byWidth, byHeight), 196), 288)
        switch state.playerState {
        case .error, .loading: return max(196, base - 28)
        default: return base
        }
    }

    // MARK: 有曲目

    private func playingContent(art: CGFloat, width: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            cover(size: art)

            Spacer().frame(height: compact ? 14 : 22)

            trackInfo

            Spacer().frame(height: compact ? 9 : 14)

            chips

            Spacer().frame(height: compact ? 13 : 20)

            progressBlock(width: min(width * 0.56, 420))

            Spacer().frame(height: compact ? 10 : 16)

            transport(compact: compact)

            PlaybackControlStatus()

            Spacer().frame(height: compact ? 8 : 14)

            volumeBlock

            if !compact {
                Spacer().frame(height: DS.Space.xl)
                nextUp
            }
        }
        .padding(.horizontal, DS.Space.xxxl)
    }

    private func cover(size: CGFloat) -> some View {
        ZStack {
            // 一团音乐色的光, 把封面从背景里托起来。
            Circle()
                .fill(tint.opacity(isDark ? 0.28 : 0.16))
                .frame(width: size * 1.02, height: size * 1.02)
                .blur(radius: size * 0.26)

            CoverArtwork(url: state.currentCoverURL,
                         size: size,
                         radius: DS.Radius.artHero,
                         shadow: true,
                         borderOpacity: isDark ? 0.14 : 0.22)
        }
        .frame(width: size, height: size)
    }

    private var trackInfo: some View {
        VStack(spacing: DS.Space.s) {
            Text(state.trackStatus.title)
                .font(DS.TypeScale.heroTitle)
                .tracking(DS.Tracking.display)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(artistLine)
                .font(.system(size: 13, weight: .medium))
                .tracking(DS.Tracking.tight)
                // 浅色模式下的副标题需要 ≥4.5:1 对比度, 用 textPrimary 压到 0.78。
                .foregroundStyle(isDark ? DS.Palette.textSecondary
                                        : DS.Palette.textPrimary.opacity(0.78))
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 540)
    }

    /// 只放"格式"信息; 输出链状态(独占/位完美)由右上玻璃胶囊负责, 避免重复。
    private var chips: some View {
        HStack(spacing: DS.Space.s) {
            DSChip(text: levelLabel)
            if state.trackStatus.fileRate > 0 {
                DSChip(text: WindowFormatting.rate(state.trackStatus.fileRate))
            }
            if state.trackStatus.fileBits > 0 {
                DSChip(text: "\(state.trackStatus.fileBits) bit")
            }
            if !formatText.isEmpty {
                DSChip(text: formatText)
            }
        }
    }

    private func progressBlock(width: CGFloat) -> some View {
        let total = max(state.trackStatus.seconds, 0)
        let position = scrubbing.map { $0 * total } ?? state.trackStatus.positionSeconds
        let fraction = total > 0 ? min(max(position / total, 0), 1) : 0
        return VStack(spacing: DS.Space.m) {
            DSSeekBar(progress: fraction, tint: tint, height: 4, buffered: state.trackStatus.downloadFraction,
                      onScrub: { value in
                          state.seek(to: value * total)
                          scrubbing = nil
                      },
                      onScrubbing: { scrubbing = $0 })
            HStack {
                Text(WindowFormatting.timecode(position))
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer(minLength: DS.Space.m)
                Text(WindowFormatting.timecode(total))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .font(DS.TypeScale.timecodeLarge)
        }
        .frame(width: width)
        .disabled(total <= 0)
        .opacity(total > 0 ? 1 : 0.45)
    }

    private func transport(compact: Bool) -> some View {
        HStack(spacing: compact ? DS.Space.xxl : DS.Space.xxl + DS.Space.s) {
            DSIconButton(systemName: "backward.fill", size: 36, iconSize: 17,
                         help: "上一首") { state.playPrevious() }
                .opacity(hasTrack ? 1 : 0.35)
                .disabled(!hasTrack)

            DSPlayButton(isPlaying: isPlaying, size: compact ? 50 : 56) {
                state.playPause()
            }

            DSIconButton(systemName: "forward.fill", size: 36, iconSize: 17,
                         help: "下一首") { state.playNext() }
                .opacity(hasTrack ? 1 : 0.35)
                .disabled(!hasTrack)
        }
        .padding(.horizontal, 54)
        .overlay(alignment: .leading) { PlaybackModeButton(size: 30) }
    }

    private var volumeBlock: some View {
        DSVolumeBar(volume: Double(state.volume), tint: tint) { value in
            state.setManualVolume(Float(value))
        }
        .frame(width: 220)
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = state.nextPlaybackTitle {
            HStack(spacing: DS.Space.s) {
                Text("接下来")
                    .dsMicroLabel(DS.Palette.textTertiary)
                Text(next)
                    .font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textSecondary.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: 440)
        }
    }

    // MARK: 空状态

    private func idleContent(compact: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if isDark {
                    Circle()
                        .fill(Color.white.opacity(0.055))
                        .frame(width: 190, height: 190)
                        .blur(radius: 44)
                }
                Circle()
                    .fill(DS.Palette.surface)
                    .frame(width: compact ? 104 : 128, height: compact ? 104 : 128)
                    .overlay {
                        Circle().strokeBorder(DS.Palette.hairline, lineWidth: 1)
                    }
                    .dsShadow(DS.Shadow.panel)
                DSBrandMark(size: compact ? 40 : 48, tint: DS.Palette.textSecondary)
            }

            Spacer().frame(height: DS.Space.xxl)

            Text("让音乐安静地流过")
                .font(.system(size: 22, weight: .semibold))
                .tracking(DS.Tracking.display)
                .foregroundStyle(DS.Palette.textPrimary)

            Spacer().frame(height: DS.Space.m)

            Text("从菜单栏打开净听, 挑一首无损曲目开始播放")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(DS.Palette.textSecondary)

            Spacer().frame(height: DS.Space.xxl)

            HStack(spacing: DS.Space.s) {
                DSChip(text: "网易云", systemImage: "music.note")
                DSChip(text: "哔哩哔哩", systemImage: "play.rectangle")
                DSChip(text: "音频直链", systemImage: "link")
            }
        }
        .multilineTextAlignment(.center)
    }
}
