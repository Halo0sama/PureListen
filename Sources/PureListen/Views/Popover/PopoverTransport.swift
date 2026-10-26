import SwiftUI
import PureListenCore

// MARK: - 浮动播放台

/// 玻璃播放台：列表在上沿渐隐，保持圆角周围与玻璃背景干净。
struct PopoverTransport: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter
    @Environment(\.albumTint) private var tint

    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 6) {
            seekRow
            trackRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 7)
        .dsGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                 fallbackFill: DS.Palette.canvasElevated.opacity(0.96),
                 castsShadow: false)
        // 玻璃层的系统投影也限制在播放栏内，避免盖黑两侧与底部的列表。
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: 进度

    private var seekRow: some View {
        let total = max(state.trackStatus.seconds, 0)
        let position = scrubbing.map { $0 * total } ?? state.trackStatus.positionSeconds
        let fraction = total > 0 ? min(max(position / total, 0), 1) : 0
        return HStack(spacing: 8) {
            Text(format(position))
                .font(DS.TypeScale.timecode)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 34, alignment: .leading)
            DSSeekBar(progress: fraction, tint: tint, height: 3,
                      showsThumbAlways: false, buffered: state.trackStatus.downloadFraction,
                      onScrub: { value in
                          state.seek(to: value * total)
                          scrubbing = nil
                      },
                      onScrubbing: { scrubbing = $0 })
                .disabled(total <= 0)
            Text("-" + format(max(total - position, 0)))
                .font(DS.TypeScale.timecode)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: 曲目 + 控制

    private var trackRow: some View {
        HStack(spacing: DS.Space.m) {
            // 点曲目区 → 在面板内打开「正在播放」页（不再弹新窗口）。
            Button {
                router.openNowPlaying()
            } label: {
                HStack(spacing: DS.Space.m) {
                    CoverArtwork(url: state.currentCoverURL, size: 34,
                                 radius: DS.Radius.artSmall,
                                 borderOpacity: 0.16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hasTrack ? state.trackStatus.title : "未在播放")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(DS.Tracking.tight)
                            .foregroundStyle(hasTrack ? DS.Palette.textPrimary
                                                      : DS.Palette.textSecondary)
                            .lineLimit(1)
                        Text(detailLine)
                            .font(DS.TypeScale.meta)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("展开正在播放")

            Spacer(minLength: DS.Space.xs)

            HStack(spacing: DS.Space.xs) {
                PlaybackModeButton(size: 23)
                DSIconButton(systemName: "backward.fill", size: 26, iconSize: 11,
                             help: "上一首") { state.playPrevious() }
                    .disabled(!hasTrack)
                    .opacity(hasTrack ? 1 : 0.4)
                DSPlayButton(isPlaying: isPlaying, size: 34) { state.playPause() }
                DSIconButton(systemName: "forward.fill", size: 26, iconSize: 11,
                             help: "下一首") { state.playNext() }
                    .disabled(!hasTrack)
                    .opacity(hasTrack ? 1 : 0.4)
            }
        }
    }

    // MARK: 辅助

    private var hasTrack: Bool { !state.trackStatus.title.isEmpty }

    private var isPlaying: Bool {
        if case .playing = state.playerState { return true }
        return false
    }

    private var detailLine: String {
        let status = state.trackStatus
        if case let .loading(hint) = state.playerState { return hint }
        if case let .error(message) = state.playerState { return message }
        if status.buffering { return "缓冲中…" }
        guard hasTrack else {
            return "从歌单里挑一首开始"
        }
        var parts: [String] = []
        if !status.artist.isEmpty { parts.append(status.artist) }
        if status.fileRate > 0 { parts.append(WindowFormatting.rate(status.fileRate)) }
        if !status.level.isEmpty { parts.append(WindowFormatting.levelShort(status.level, fallback: state.level)) }
        return parts.joined(separator: " · ")
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
