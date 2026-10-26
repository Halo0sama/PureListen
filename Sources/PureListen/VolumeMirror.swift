import Foundation
import PureListenCore

/// 只同步同一系统输出设备上的音量调节；切换、静音恢复与设备初始化只重设基线。
final class VolumeMirror {
    struct Snapshot: Equatable {
        var deviceID: UInt32
        var uid: String
        var volume: Float
    }

    var onSystemVolume: ((Float) -> Void)?
    var fallbackDevice: (() -> SystemOutput.Identity?)?
    private var timer: Timer?
    private var lastSnapshot: Snapshot?
    private var settlingUntil = Date.distantPast
    private let pollInterval: TimeInterval
    private let readSnapshotOverride: (() -> Snapshot?)?
    private let now: () -> Date

    init(pollInterval: TimeInterval = 0.4,
         readSnapshot: (() -> Snapshot?)? = nil, now: @escaping () -> Date = Date.init) {
        self.pollInterval = pollInterval
        self.readSnapshotOverride = readSnapshot
        self.now = now
    }

    private func readSnapshot() -> Snapshot? {
        if let readSnapshotOverride { return readSnapshotOverride() }
        // 独占所有输出时，CoreAudio 的默认输出可能暂时为 0。
        return Self.snapshot(defaultDevice: SystemOutput.defaultOutputIdentity(),
                             fallbackDevice: fallbackDevice?(), volume: SystemOutput.volume(on:))
    }

    static func snapshot(defaultDevice: SystemOutput.Identity?, fallbackDevice: SystemOutput.Identity?,
                         volume: (UInt32) -> Float?) -> Snapshot? {
        for device in [defaultDevice, fallbackDevice].compactMap({ $0 }) {
            guard let value = volume(device.id), value.isFinite, (0...1).contains(value) else { continue }
            return Snapshot(deviceID: device.id, uid: device.uid, volume: value)
        }
        return nil
    }

    func start() {
        guard timer == nil else { return }
        rebase()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastSnapshot = nil
    }

    /// 自身静音/恢复、设备事件与起播不会被误认为用户调节。
    func rebase() {
        lastSnapshot = readSnapshot()
        settlingUntil = now().addingTimeInterval(2)
    }

    func tick() {
        guard let snapshot = readSnapshot(), snapshot.volume.isFinite,
              (0...1).contains(snapshot.volume) else {
            lastSnapshot = nil
            return
        }
        defer { lastSnapshot = snapshot }
        guard let previous = lastSnapshot,
              previous.deviceID == snapshot.deviceID, previous.uid == snapshot.uid else {
            settlingUntil = now().addingTimeInterval(2)
            return
        }
        guard now() >= settlingUntil, snapshot.volume != previous.volume else { return }
        onSystemVolume?(snapshot.volume)
    }
}
