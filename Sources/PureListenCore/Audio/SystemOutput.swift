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

    /// 设置系统静音。优先用设备的 mute 属性（保留音量百分比，音量联动不受影响）；
    /// 设备没有 mute 属性时退回"音量归零 + 记住原值"。
    @discardableResult
    public static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDeviceID() else { return false }
        let flag: UInt32 = muted ? 1 : 0
        if isSettable(device, kAudioDevicePropertyMute) {
            return write(device, kAudioDevicePropertyMute, value: flag)
        }
        for element in 1...4 {
            let propertyElement = AudioObjectPropertyElement(element)
            if isSettable(device, kAudioDevicePropertyMute, element: propertyElement) {
                return write(device, kAudioDevicePropertyMute,
                             element: propertyElement, value: flag)
            }
        }

        // 兜底：用音量 0 模拟静音，并记住原音量以便恢复。
        if muted {
            if mutedFallbackVolume == nil { mutedFallbackVolume = volume() }
            return setVolume(0)
        } else {
            defer { mutedFallbackVolume = nil }
            if let saved = mutedFallbackVolume { return setVolume(saved) }
            return true
        }
    }

    // MARK: - 内部

    /// 设备没有 mute 属性时，记录静音前的音量。
    private static var mutedFallbackVolume: Float?

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
