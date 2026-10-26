import SwiftUI
import PureListenCore

// MARK: - 浮动播放台

/// 玻璃播放台: 浮在列表之上, 内容从它下方滚过 —— Golden Gate 的标志性层次。
struct PopoverTransport: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter
    @Environment(\.albumTint) private var tint

    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 6) {
            seekRow
            trackRow
            volumeRow
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
                      showsThumbAlways: false,
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
                                 radius: DS.Radius.artSmall, shadow: true,
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

    // MARK: 音量

    private var volumeRow: some View {
        HStack(spacing: DS.Space.s) {
            DSVolumeBar(volume: Double(state.volume), tint: tint) { value in
                state.setManualVolume(Float(value))
            }
            if hasTrack, state.player.bitPerfect {
                DSChip(text: "位完美", systemImage: "checkmark.seal.fill", tone: .mint,
                       compact: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(DS.Motion.quick, value: state.player.bitPerfect)
    }

    private var rateShort: String {
        let status = state.trackStatus
        guard status.fileRate > 0 else { return "—" }
        return String(format: "%.4g/%d", Double(status.fileRate) / 1000, status.fileBits)
    }

    private var levelShort: String {
        switch state.level {
        case .hires: return "Hi-Res"
        case .lossless: return "无损"
        case .exhigh: return "320k"
        case .standard: return "128k"
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
        guard hasTrack else {
            if case let .loading(hint) = state.playerState { return hint }
            if case let .error(message) = state.playerState { return message }
            return "从歌单里挑一首开始"
        }
        guard hasTrack else { return "" }
        var parts: [String] = []
        if !status.artist.isEmpty { parts.append(status.artist) }
        parts.append("\(levelShort) \(rateShort)")
        return parts.joined(separator: " · ")
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
