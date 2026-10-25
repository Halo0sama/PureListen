import SwiftUI
import PureListenCore

// MARK: - 文案 / 数字格式

/// 窗口内的显示格式。只做展示, 不改任何状态。
enum WindowFormatting {

    /// 0:00 风格的等宽时间码。
    static func timecode(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 44100 → 44.1 kHz
    static func rate(_ hz: Int) -> String {
        guard hz > 0 else { return "—" }
        let value = Double(hz) / 1000
        if abs(value.rounded() - value) < 0.01 {
            return String(format: "%.0f kHz", value)
        }
        return String(format: "%.1f kHz", value)
    }

    /// 44100 / 16 → "44.1 kHz · 16 bit"
    static func spec(rate: Int, bits: Int) -> String {
        guard rate > 0 else { return "—" }
        guard bits > 0 else { return self.rate(rate) }
        return "\(self.rate(rate)) · \(bits) bit"
    }

    /// 音质档位短标签。
    static func levelShort(_ level: NCLevel) -> String {
        switch level {
        case .lossless: return "无损"
        case .hires: return "Hi-Res"
        case .exhigh: return "极高"
        case .standard: return "标准"
        }
    }

    /// 流内报告的档位字符串有时是 "lossless" / "hires"。
    static func levelShort(_ raw: String, fallback: NCLevel) -> String {
        switch raw.lowercased() {
        case "lossless": return "无损"
        case "hires", "hi-res": return "Hi-Res"
        case "exhigh": return "极高"
        case "standard": return "标准"
        case "": return levelShort(fallback)
        default: return raw
        }
    }

    /// 缓冲百分比; 容量为 0(尚未起播)时返回 nil。
    static func bufferPercent(available: Int, capacity: Int) -> Int? {
        guard capacity > 0 else { return nil }
        return min(max(Int(Double(available) / Double(capacity) * 100), 0), 100)
    }
}

// MARK: - 页头

/// 内容区顶部的工具栏条: 左侧页面标题, 高度与窗口 chrome 对齐(52pt)。
///
/// 窗口没有原生 toolbar, 这一行就是它的替代 —— 克制的一行字, 让每个页面都有落点。
struct WindowPageToolbar: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(DS.Tracking.tight)
                .foregroundStyle(DS.Palette.textSecondary)
            if let detail {
                Text(detail)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.m)
        }
        .padding(.horizontal, DS.Space.windowPadding)
        .frame(height: DS.Size.toolbarHeight)
    }
}

// MARK: - 音质胶囊

/// 窗口右上角浮动的玻璃胶囊: 输出状态摘要。
///
/// 全局唯一一层玻璃 —— 它浮在氛围背景上, 取色来自封面。
/// 信息职责: 徽标行负责"格式"(无损 / 采样率 / FLAC), 胶囊负责"输出链状态"
/// (独占输出 · 位完美), 两者不重复。
struct WindowQualityCapsule: View {
    @EnvironmentObject var state: AppState

    private var isPlaying: Bool {
        if case .playing = state.playerState { return true }
        return false
    }

    private var isHealthy: Bool {
        state.trackStatus.exclusive && !state.trackStatus.resampled && state.player.bitPerfect
    }

    private var routing: String {
        state.trackStatus.exclusive ? "独占输出" : "共享输出"
    }

    private var fidelity: String {
        if state.trackStatus.resampled { return "设备降采样" }
        return state.player.bitPerfect ? "位完美" : "数字衰减"
    }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            DSStatusDot(color: isHealthy ? DS.Palette.mint : DS.Palette.amber,
                        isLive: isPlaying, diameter: 4.5)
            Text(routing)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text("·")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(fidelity)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 28)
        .dsGlass(in: Capsule(style: .continuous), interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("输出状态: \(routing), \(fidelity)")
    }
}


// MARK: - 窗口激活

/// 窗口出现时把 App 与窗口带到前台。
///
/// 真实使用时窗口由 `NowPlayingWindowController` 激活; 截图模式下窗口由预览工作室直接创建,
/// 需要视图自己激活一次, 否则 macOS 会把控件画成"非活动窗口"样式(开关 ON 态变灰)。
struct WindowActivationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
