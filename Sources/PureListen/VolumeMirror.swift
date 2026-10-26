import AppKit
import Foundation
import PureListenCore

/// 系统音量联动: 轮询系统输出设备的音量, 变化时同步到 App 软件音量。
///
/// 直接读 CoreAudio 属性（`SystemOutput`），不再使用 AppleScript：
/// AppleScript 会触发 macOS 的「自动化 / 设备控制和数据访问」授权，而净听是 ad-hoc 签名，
/// 授权无法跨构建保持，0.4 秒一次的轮询会导致授权弹窗反复出现。
/// CoreAudio 读取不需要任何权限，也不会产生声音。
final class VolumeMirror {
    /// 每次系统音量变化时回调(0...1)。
    var onSystemVolume: ((Float) -> Void)?
    private var timer: Timer?
    private var lastValue: Float = -1
    private let pollInterval: TimeInterval

    init(pollInterval: TimeInterval = 0.4) {
        self.pollInterval = pollInterval
    }

    func start() {
        guard timer == nil else { return }
        lastValue = readSystemVolume() ?? -1
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let value = readSystemVolume(), value != lastValue else { return }
        lastValue = value
        onSystemVolume?(value)
    }

    /// 读取系统默认输出设备的音量（0...1），直接走 CoreAudio，无权限、无 Apple Event。
    private func readSystemVolume() -> Float? {
        SystemOutput.volume()
    }
}
