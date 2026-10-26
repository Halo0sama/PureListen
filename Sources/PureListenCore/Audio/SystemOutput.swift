import CoreAudio
import Foundation

/// 系统默认输出设备的音量 / 静音读写。
///
/// 为什么直接走 CoreAudio，而不用 `NSAppleScript`：
/// AppleScript 发送 Apple Event 在 macOS 26+ 被归入「自动化 / 设备控制和数据访问」TCC 权限。
/// 净听是 ad-hoc 签名（每次构建 cdhash 变化），TCC 里的授权记录无法稳定匹配新签名，
/// 于是每次执行脚本都会重新弹授权窗 —— `VolumeMirror` 每 0.4 秒轮询一次，就变成了"反复弹窗"。
/// 直接读写 CoreAudio 设备属性不需要任何 TCC 授权，也不会产生声音。
///
/// 线程约定：这些函数的调用都发生在主线程（音量轮询、播放状态回调），内部不加锁。
public enum SystemOutput {

    // MARK: - 默认输出设备

    public static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice,
                              scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    public struct Identity: Equatable {
        public let id: AudioDeviceID
        public let uid: String
        public init(id: AudioDeviceID, uid: String) { self.id = id; self.uid = uid }
    }

    public static func defaultOutputIdentity() -> Identity? {
        guard let id = defaultOutputDeviceID(), let uid = AudioDevice.uid(for: id) else { return nil }
        return Identity(id: id, uid: uid)
    }

    /// 默认输出设备的可读名字（诊断用）。
    public static func defaultOutputDeviceName() -> String? {
        guard let device = defaultOutputDeviceID() else { return nil }
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var name: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    // MARK: - 音量 (0...1)

    public static func volume() -> Float? {
        guard let device = defaultOutputDeviceID() else { return nil }
        return volume(on: device)
    }

    public static func volume(on device: AudioDeviceID) -> Float? {
        if let main: Float32 = read(device, kAudioDevicePropertyVolumeScalar) {
            return clamp(main)
        }
        // 部分设备只在声道元素上暴露音量，取平均。
        let channels = [1, 2, 3, 4].compactMap { element -> Float32? in
            read(device, kAudioDevicePropertyVolumeScalar, element: AudioObjectPropertyElement(element))
        }
        guard !channels.isEmpty else { return nil }
        return clamp(channels.reduce(0, +) / Float32(channels.count))
    }

    @discardableResult
    public static func setVolume(_ value: Float) -> Bool {
        guard let device = defaultOutputDeviceID() else { return false }
        let volume = clamp(value)
        if isSettable(device, kAudioDevicePropertyVolumeScalar) {
            return write(device, kAudioDevicePropertyVolumeScalar, value: volume)
        }
        var applied = false
        for element in 1...4 {
            let propertyElement = AudioObjectPropertyElement(element)
            if isSettable(device, kAudioDevicePropertyVolumeScalar, element: propertyElement) {
                applied = write(device, kAudioDevicePropertyVolumeScalar,
                                element: propertyElement, value: volume) || applied
            }
        }
        return applied
    }

    // MARK: - 静音

    public static func isMuted() -> Bool? {
        guard let device = defaultOutputDeviceID() else { return nil }
        return isMuted(on: device)
    }

    public static func isMuted(on device: AudioDeviceID) -> Bool? {
        if let main: UInt32 = read(device, kAudioDevicePropertyMute) {
            return main != 0
        }
        let channels = [1, 2, 3, 4].compactMap { element -> UInt32? in
            read(device, kAudioDevicePropertyMute, element: AudioObjectPropertyElement(element))
        }
        guard !channels.isEmpty else { return nil }
        // 任一主声道静音即视为系统静音。
        return channels.contains { $0 != 0 }
    }

    /// 保护会话绑定实际被修改设备的 ID + UID；不能把旧设备的静音/音量恢复到新默认输出。
    public struct MuteSession {
        public let device: Identity
        struct Control {
            let selector: AudioObjectPropertySelector
            let element: AudioObjectPropertyElement
            let original: Float
        }
        let controls: [Control]
        public var originalMute: Bool? {
            let muteControls = controls.filter { $0.selector == kAudioDevicePropertyMute }
            return muteControls.isEmpty ? nil : muteControls.contains { $0.original != 0 }
        }
        /// 系统保护置 1；独占播放临时解除设备硬件静音时置 0。
        var activeMuteValue: Float = 1
        var uidForDevice: (AudioDeviceID) -> String? = AudioDevice.uid(for:)
        var writeControl: (AudioDeviceID, AudioObjectPropertySelector, AudioObjectPropertyElement, Float) -> Bool = { id, selector, element, value in
            if selector == kAudioDevicePropertyMute {
                return SystemOutput.write(id, selector, element: element, value: UInt32(value))
            }
            return SystemOutput.write(id, selector, element: element, value: value)
        }
        var readControl: ((AudioDeviceID, AudioObjectPropertySelector, AudioObjectPropertyElement) -> Float?)?

        @discardableResult
        public func ensureMuted() -> Bool { apply(restoring: false) }

        @discardableResult
        public func apply() -> Bool { apply(restoring: false) }

        @discardableResult
        public func restore() -> Bool { apply(restoring: true) }

        private func apply(restoring: Bool) -> Bool {
            guard uidForDevice(device.id) == device.uid else { return false }
            var applied = true
            for control in controls {
                let value = restoring ? control.original : (control.selector == kAudioDevicePropertyMute ? activeMuteValue : 0)
                applied = writeControl(device.id, control.selector, control.element, value) && applied
            }
            guard applied, let readControl else { return applied }
            // USB 控制异步生效；写入成功不代表设备已经解除/恢复静音。
            var matches = 0
            for _ in 0..<40 {
                let correct = controls.allSatisfy { control in
                    let expected = restoring ? control.original : (control.selector == kAudioDevicePropertyMute ? activeMuteValue : 0)
                    guard let actual = readControl(device.id, control.selector, control.element) else { return false }
                    return abs(actual - expected) < 0.00001
                }
                matches = correct ? matches + 1 : 0
                if matches >= 2 { return true }
                usleep(5_000)
            }
            for control in controls {
                NCLog.log("[静音回读失败] 恢复=\(restoring) 原值=\(control.original) 活动值=\(activeMuteValue) 现值=\(String(describing: readControl(device.id, control.selector, control.element)))")
            }
            return false
        }
    }

    /// 在获取独占前捕获硬件 mute；调用 apply() 解除静音，结束后 restore() 还原。
    public static func playbackUnmuteSession(on device: Identity) throws -> MuteSession? {
        guard AudioDevice.uid(for: device.id) == device.uid else {
            throw NSError(domain: "SystemOutput", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "输出设备已断开"])
        }
        var controls: [MuteSession.Control] = []
        for element: AudioObjectPropertyElement in 0...32 {
            guard let value: UInt32 = read(device.id, kAudioDevicePropertyMute, element: element) else { continue }
            // 已静音但不可解除时，明确失败，避免界面显示播放却无声。
            guard isSettable(device.id, kAudioDevicePropertyMute, element: element) else {
                if value != 0 {
                    throw NSError(domain: "SystemOutput", code: -2,
                                  userInfo: [NSLocalizedDescriptionKey: "输出设备处于硬件静音，请先解除设备静音"])
                }
                continue
            }
            controls.append(.init(selector: kAudioDevicePropertyMute, element: element, original: Float(value)))
        }
        guard !controls.isEmpty else { return nil } // 没有硬件 mute 的设备仍可播放。
        return MuteSession(device: device, controls: controls, activeMuteValue: 0, readControl: controlValue)
    }

    public static func beginMuteSession(on device: Identity) -> MuteSession? {
        guard AudioDevice.uid(for: device.id) == device.uid else { return nil }
        var controls: [MuteSession.Control] = []
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            for element: AudioObjectPropertyElement in [0, 1, 2, 3, 4] {
                guard isSettable(device.id, selector, element: element) else { continue }
                let original: Float?
                if selector == kAudioDevicePropertyMute {
                    let value: UInt32? = read(device.id, selector, element: element)
                    original = value.map { Float($0) }
                } else {
                    original = read(device.id, selector, element: element)
                }
                guard let original, original.isFinite else { continue }
                controls.append(MuteSession.Control(selector: selector, element: element, original: original))
                if element == 0 { break }
            }
            if !controls.isEmpty { break } // 有 mute 属性时保留硬件音量；否则保存每个声道的原音量。
        }
        guard !controls.isEmpty else { return nil }
        let session = MuteSession(device: device, controls: controls, readControl: controlValue)
        guard session.ensureMuted() else {
            session.restore()
            return nil
        }
        return session
    }

    // MARK: - 内部

    private static func controlValue(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                     _ element: AudioObjectPropertyElement) -> Float? {
        if selector == kAudioDevicePropertyMute {
            let value: UInt32? = read(device, selector, element: element)
            // 明确做数值转换；map(Float.init) 可能选中 init(bitPattern:)。
            return value.map { Float($0) }
        }
        return read(device, selector, element: element)
    }

    private static let outputScope = kAudioDevicePropertyScopeOutput

    private static func address(_ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = outputScope,
                               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func read<T>(_ device: AudioDeviceID,
                                _ selector: AudioObjectPropertySelector,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> T? {
        var property = address(selector, element: element)
        guard AudioObjectHasProperty(device, &property) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, buffer) == noErr,
              size == UInt32(MemoryLayout<T>.size) else { return nil }
        return buffer.load(as: T.self)
    }

    private static func isSettable(_ device: AudioDeviceID,
                                   _ selector: AudioObjectPropertySelector,
                                   element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> Bool {
        var property = address(selector, element: element)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &property, &settable) == noErr
            && settable.boolValue
    }

    private static func write<T>(_ device: AudioDeviceID,
                                 _ selector: AudioObjectPropertySelector,
                                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                                 value: T) -> Bool {
        var property = address(selector, element: element)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var mutableValue = value
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeBytes(of: &mutableValue) { raw -> OSStatus in
            guard let base = raw.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectSetPropertyData(device, &property, 0, nil, size, base)
        }
        return status == noErr
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
