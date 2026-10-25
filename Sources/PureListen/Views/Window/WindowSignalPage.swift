import SwiftUI
import PureListenCore

// MARK: - 「播放链路」页

/// 竖向信号流: 音源 → 解码 → 缓冲 → 独占输出 → 设备, 底部一张端到端结论卡。
///
/// 这一页是净听"为什么好听"的可视化: 每一步都可见, 每个数值都是真的。
/// 颜色克制: 节点图标一律中性, 只有 mint(健康)与 amber(降采样)两种状态色。
struct WindowSignalPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dsIsDark) private var isDark

    private var hasTrack: Bool { !state.trackStatus.title.isEmpty }

    /// 内容层是实体表面: 深色下压到近乎墨色的浮板, 浅色下是纸白卡片。
    private var cardFill: Color {
        isDark ? DS.Palette.canvasElevated.opacity(0.60) : DS.Palette.surface
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowPageToolbar(title: "播放链路",
                              detail: hasTrack ? "音源 → 解码 → 缓冲 → 独占 → 设备" : nil)
            if hasTrack {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    chainContent
                }
            } else {
                emptyState
            }
        }
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
                Spacer().frame(height: DS.Space.xl)
                conclusionCard
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, DS.Space.windowPadding)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var outputTone: Color {
        state.trackStatus.resampled ? DS.Palette.amber : DS.Palette.mint
    }

    // MARK: 节点

    private var nodes: [WindowSignalNode] {
        let status = state.trackStatus
        let stats = state.player.ringStats()
        let percent = WindowFormatting.bufferPercent(available: stats.available,
                                                     capacity: stats.capacity)
        let deviceRate = status.deviceRate > 0
            ? status.deviceRate
            : Int(state.selectedDevice?.currentRate ?? 0)
        let deviceName = state.selectedDevice?.name ?? "输出设备"
        let format = status.format.isEmpty ? "PCM" : status.format.uppercased()
        let source = state.currentSourceLabel
        let playlist = state.currentPlaylist?.name ?? ""

        return [
            WindowSignalNode(
                symbol: "music.note",
                title: source,
                detail: playlist.isEmpty ? "网易云音乐 · 曲库" : playlist,
                trailing: WindowFormatting.levelShort(status.level, fallback: state.level),
                badge: .none,
                isStatus: false
            ),
            WindowSignalNode(
                symbol: "waveform",
                title: "\(format) 解码",
                detail: WindowFormatting.spec(rate: status.fileRate, bits: status.fileBits),
                trailing: status.fileRate > 0 ? WindowFormatting.rate(status.fileRate) : "—",
                badge: status.fileRate > 0 ? .ok : .none,
                isStatus: false
            ),
            WindowSignalNode(
                symbol: "memorychip",
                title: "无锁环形缓冲",
                detail: percent.map { "已缓冲 \($0)%, 解码与输出解耦" } ?? "解码线程与 IO 线程无锁交接",
                trailing: percent.map { "\($0)%" } ?? "就绪",
                badge: percent == nil ? .none : .ok,
                isStatus: true
            ),
            WindowSignalNode(
                symbol: "lock.shield",
                title: "Hog Mode 独占输出",
                detail: status.exclusive ? "设备已独占 · 绕过系统混音器" : "未取得独占, 输出经过系统混音",
                trailing: status.resampled ? "降采样" : (status.exclusive ? "原生" : "共享"),
                badge: status.resampled || !status.exclusive ? .warn : .ok,
                isStatus: true
            ),
            WindowSignalNode(
                symbol: "headphones",
                title: deviceName,
                detail: "\(WindowFormatting.rate(deviceRate)) · 直写设备",
                trailing: deviceRate > 0 ? WindowFormatting.rate(deviceRate) : "—",
                badge: state.selectedDevice == nil ? .warn : .ok,
                isStatus: false
            ),
        ]
    }

    private func nodeCard(_ node: WindowSignalNode) -> some View {
        HStack(spacing: DS.Space.l) {
            neutralGlyph(node.symbol)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(node.title)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Text(node.detail)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.m)

            trailingView(node)
        }
        .padding(.horizontal, DS.Space.l + DS.Space.xxs)
        .frame(height: 52)
        .dsSurface(DS.Radius.card, fill: cardFill)
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
                    .font(.system(size: 12.5, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private func trailingView(_ node: WindowSignalNode) -> some View {
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
                .frame(width: 1, height: 16)
                .overlay {
                    Circle()
                        .fill(color)
                        .frame(width: DS.Space.xs, height: DS.Space.xs)
                }
                .padding(.leading, 28)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    // MARK: 结论

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
        }
        .padding(DS.Space.l + DS.Space.xs)
        .dsSurface(DS.Radius.card, fill: cardFill)
    }

    private func conclusionHeadline(resampled: Bool, exclusive: Bool) -> String {
        if resampled { return "设备不支持原生采样率, 已降采样" }
        if exclusive { return "信号完整送达耳机" }
        return "输出经过系统混音器"
    }

    private func conclusionDetail(resampled: Bool, exclusive: Bool, bitPerfect: Bool) -> String {
        let status = state.trackStatus
        var parts: [String] = []
        if status.fileRate > 0 {
            parts.append("\(WindowFormatting.rate(status.fileRate)) 原生直通")
        }
        if status.fileBits > 0 {
            parts.append("\(status.fileBits) bit")
        }
        parts.append(exclusive ? "Hog Mode 独占" : "系统混音")
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

private struct WindowSignalNode {
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
