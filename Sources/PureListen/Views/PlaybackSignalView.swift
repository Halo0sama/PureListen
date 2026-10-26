import SwiftUI
import PureListenCore

/// 窗口与小播放器共享的链路，紧凑布局只调整尺寸，不另造一套播放数据。
struct PlaybackSignalView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dsIsDark) private var isDark
    var compact = false

    private var hasTrack: Bool { !state.trackStatus.title.isEmpty }
    private var isPlaying: Bool { state.playerState == .playing }
    private var cardFill: Color {
        isDark ? DS.Palette.canvasElevated.opacity(0.60) : DS.Palette.surface
    }

    var body: some View {
        Group {
            if hasTrack {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in chainContent }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 内容

    private var chainContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    nodeCard(node)
                    if index < nodes.count - 1 {
                        connector(color: index == nodes.count - 2 ? outputTone : DS.Palette.mint)
                    }
                }
                Spacer().frame(height: compact ? 14 : DS.Space.xl)
                if compact {
                    compactConclusionCard
                } else {
                    conclusionCard
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, compact ? 0 : DS.Space.windowPadding)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, compact ? 8 : DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var outputTone: Color {
        state.trackStatus.resampled ? DS.Palette.amber : DS.Palette.mint
    }

    // MARK: 节点

    private var nodes: [PlaybackSignalNode] {
        let status = state.trackStatus
        let exclusive = isPlaying && status.exclusive
        let stats = state.player.ringStats()
        let percent = WindowFormatting.bufferPercent(available: stats.available,
                                                     capacity: stats.capacity)
        let deviceRate = status.deviceRate > 0
            ? status.deviceRate
            : Int(state.selectedDevice?.currentRate ?? 0)
        let deviceName = state.selectedDevice?.name ?? "输出设备未连接"
        let format = status.format.isEmpty ? "PCM" : status.format.uppercased()
        let source = state.currentSourceLabel
        let sourceDetail = state.currentItem?.title ?? state.currentPlaylist?.name ?? "网易云音乐 · 曲库"

        return [
            PlaybackSignalNode(
                symbol: "music.note",
                title: source,
                detail: sourceDetail,
                trailing: WindowFormatting.levelShort(status.level, fallback: state.level),
                badge: .none,
                isStatus: false
            ),
            PlaybackSignalNode(
                symbol: "waveform",
                title: "\(format) 解码",
                detail: WindowFormatting.spec(rate: status.fileRate, bits: status.fileBits),
                trailing: status.fileRate > 0 ? WindowFormatting.rate(status.fileRate) : "—",
                badge: status.fileRate > 0 ? .ok : .none,
                isStatus: false
            ),
            PlaybackSignalNode(
                symbol: "memorychip",
                title: "无锁环形缓冲",
                detail: percent.map { "已缓冲 \($0)%, 解码与输出解耦" } ?? "解码线程与 IO 线程无锁交接",
                trailing: percent.map { "\($0)%" } ?? "等待",
                badge: percent == nil ? .none : .ok,
                isStatus: true
            ),
            PlaybackSignalNode(
                symbol: "lock.shield",
                title: "Hog Mode 独占输出",
                detail: exclusive ? "设备已独占 · 绕过系统混音器" : "独占已释放，等待播放",
                trailing: !isPlaying ? "未输出" : (status.resampled ? "降采样" : (exclusive ? "原生" : "未独占")),
                badge: !isPlaying ? .none : (status.resampled || !exclusive ? .warn : .ok),
                isStatus: true
            ),
            PlaybackSignalNode(
                symbol: "headphones",
                title: deviceName,
                detail: "\(WindowFormatting.rate(deviceRate)) · \(isPlaying ? "直写设备" : "上次输出")",
                trailing: deviceRate > 0 ? WindowFormatting.rate(deviceRate) : "—",
                badge: state.selectedDevice == nil ? .warn : .ok,
                isStatus: false
            ),
        ]
    }

    private func nodeCard(_ node: PlaybackSignalNode) -> some View {
        HStack(spacing: compact ? 9 : DS.Space.l) {
            neutralGlyph(node.symbol)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(node.title)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Text(node.detail)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: compact ? 4 : DS.Space.m)

            trailingView(node)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, compact ? 10 : DS.Space.l + DS.Space.xxs)
        .frame(height: compact ? 48 : 52)
        .dsSurface(DS.Radius.card, fill: cardFill)
        .help("\(node.title)：\(node.detail) · \(node.trailing)")
    }

    /// 节点图标一律中性: 链路页只有 mint / amber 两种状态色。
    private func neutralGlyph(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.artSmall, style: .continuous)
            .fill(DS.Palette.surfaceSelected)
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.artSmall, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 11 : 12.5, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(width: compact ? 25 : 28, height: compact ? 25 : 28)
    }

    @ViewBuilder
    private func trailingView(_ node: PlaybackSignalNode) -> some View {
        if node.isStatus {
            switch node.badge {
            case .ok:
                DSChip(text: node.trailing, tone: .mint, compact: true)
            case .warn:
                DSChip(text: node.trailing, tone: .amber, compact: true)
            case .none:
                Text(node.trailing)
                    .font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        } else {
            HStack(spacing: DS.Space.xs + 1) {
                switch node.badge {
                case .ok:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Palette.mint)
                case .warn:
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Palette.amber)
                case .none:
                    EmptyView()
                }
                Text(node.trailing)
                    .font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    /// 节点之间的连接线: 1pt 细线 + 中心小圆点, 对齐左侧图标块的中线。
    private func connector(color: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color.opacity(0.30))
                .frame(width: 1, height: compact ? 10 : 16)
                .overlay {
                    Circle()
                        .fill(color)
                        .frame(width: DS.Space.xs, height: DS.Space.xs)
                }
                .padding(.leading, compact ? 22 : 28)
            Spacer(minLength: 0)
        }
        .frame(height: compact ? 10 : 16)
    }

    // MARK: 结论

    private var compactConclusionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conclusionHeadline(resampled: state.trackStatus.resampled,
                                    exclusive: state.trackStatus.exclusive))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            if isPlaying {
                HStack(spacing: 6) {
                    DSChip(text: state.trackStatus.resampled ? "存在重采样" : "无重采样",
                           tone: state.trackStatus.resampled ? .amber : .mint, compact: true)
                    DSChip(text: state.player.bitPerfect ? "无数字衰减" : "音量 \(Int((state.volume * 100).rounded()))% · 数字衰减",
                           tone: state.player.bitPerfect ? .mint : .neutral, compact: true)
                }
            }
            Text(conclusionDetail(resampled: state.trackStatus.resampled,
                                  exclusive: state.trackStatus.exclusive,
                                  bitPerfect: state.player.bitPerfect))
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dsSurface(DS.Radius.card, fill: cardFill)
    }

    private var conclusionCard: some View {
        let resampled = state.trackStatus.resampled
        let exclusive = state.trackStatus.exclusive
        let bitPerfect = state.player.bitPerfect
        let tone: Color = resampled ? DS.Palette.amber : DS.Palette.mint

        return HStack(alignment: .top, spacing: DS.Space.l) {
            DSGlyphTile(systemName: resampled ? "exclamationmark.triangle.fill"
                                              : "checkmark.seal.fill",
                        tint: tone, size: 30)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("端到端结论")
                    .dsMicroLabel(DS.Palette.textTertiary)
                Text(conclusionHeadline(resampled: resampled, exclusive: exclusive))
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(conclusionDetail(resampled: resampled, exclusive: exclusive,
                                      bitPerfect: bitPerfect))
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Spacer(minLength: DS.Space.m)

            if isPlaying {
                VStack(alignment: .trailing, spacing: DS.Space.s) {
                    DSChip(text: resampled ? "存在 SRC" : "SRC 已消除",
                           systemImage: resampled ? "exclamationmark.triangle.fill" : "checkmark",
                           tone: resampled ? .amber : .mint)
                    if bitPerfect {
                        DSChip(text: "位完美", systemImage: "checkmark.seal.fill", tone: .mint)
                    } else {
                        DSChip(text: "数字衰减", tone: .amber)
                    }
                }
            } else {
                DSChip(text: "未输出", tone: .neutral)
            }
        }
        .padding(DS.Space.l + DS.Space.xs)
        .dsSurface(DS.Radius.card, fill: cardFill)
    }

    private func conclusionHeadline(resampled: Bool, exclusive: Bool) -> String {
        if !isPlaying { return "等待播放，当前未输出" }
        if resampled { return "设备不支持原生采样率, 已降采样" }
        if exclusive { return "音频通过独占通道输出" }
        return "尚未取得设备独占"
    }

    private func conclusionDetail(resampled: Bool, exclusive: Bool, bitPerfect: Bool) -> String {
        let status = state.trackStatus
        guard isPlaying else { return "保留上次音源信息，点击播放后更新输出状态。" }
        var parts: [String] = []
        if status.fileRate > 0 {
            parts.append("音源 \(WindowFormatting.rate(status.fileRate))")
        }
        if status.fileBits > 0 {
            parts.append("\(status.fileBits) bit")
        }
        parts.append(exclusive ? "Hog Mode 独占" : "未独占")
        if !bitPerfect {
            parts.append("音量 \(Int((state.volume * 100).rounded()))%, 有数字衰减")
        } else if !resampled {
            parts.append("无重采样 · 无数字衰减")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            DSEmptyState(systemImage: "waveform.path",
                         title: "还没有信号在流",
                         message: "播放一首歌, 这里会显示从音源到耳机的完整链路")
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 节点模型

private struct PlaybackSignalNode {
    enum Badge {
        case ok, warn, none
    }

    var symbol: String
    var title: String
    var detail: String
    var trailing: String
    var badge: Badge
    /// true: 右侧用状态胶囊(就绪/原生); false: 数值文字(44.1 kHz / 无损)。
    var isStatus: Bool
}
