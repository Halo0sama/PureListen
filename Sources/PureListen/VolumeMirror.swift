import AppKit
import Foundation

/// 系统音量联动: 轮询系统音量百分比, 变化时同步到 App 软件音量。
/// 独占(hog)期间设备不响应系统音量, 但系统音量值本身仍随音量键/设置滑块实时变化(已实测),
/// 因此 App 侧镜像该值即可实现联动, 无需任何权限。
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

    /// 读取系统输出音量百分比(0-100)。NSAppleScript 进程内执行本地 StandardAdditions, 无需授权。
    private func readSystemVolume() -> Float? {
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        let output = script?.executeAndReturnError(&error)
        if let text = output?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let number = Float(text), (0...100).contains(number) {
            return number / 100
        }
        return nil
    }
}
