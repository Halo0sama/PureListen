import Foundation
import CoreAudio
import AudioToolbox

public struct AudioDeviceInfo: Identifiable, Equatable {
    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var isBuiltIn: Bool
    public var currentRate: Double
    public var hasOutput: Bool

    public init(id: AudioDeviceID, uid: String, name: String, isBuiltIn: Bool,
                currentRate: Double, hasOutput: Bool) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.currentRate = currentRate
        self.hasOutput = hasOutput
    }
}

public enum AudioDevice {
    // MARK: - 属性读写辅助

    static func hasProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        return AudioObjectHasProperty(device, &address)
    }

    static func getPropertyData<T>(_ device: AudioDeviceID,
                                   _ selector: AudioObjectPropertySelector,
                                   _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                    alignment: MemoryLayout<T>.alignment)
        defer { data.deallocate() }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, data)
        guard status == noErr else { return nil }
        return data.assumingMemoryBound(to: T.self).pointee
    }

    static func setPropertyData<T>(_ device: AudioDeviceID,
                                   _ selector: AudioObjectPropertySelector,
                                   value: T) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return kAudioHardwareUnknownPropertyError }
        var v = value
        return withUnsafeBytes(of: &v) { ptr in
            guard let base = ptr.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(ptr.count), base)
        }
    }

    // MARK: - 设备枚举

    public static func allDevices() -> [AudioDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var count: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &count) == noErr, count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(count) / MemoryLayout<AudioDeviceID>.size)
        var realCount = count
        let result = ids.withUnsafeMutableBufferPointer { buf -> OSStatus in
            guard let base = buf.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                              &address, 0, nil, &realCount, base)
        }
        guard result == noErr else { return [] }

        var devices: [AudioDeviceInfo] = []
        for id in ids.prefix(Int(realCount) / MemoryLayout<AudioDeviceID>.size) {
            guard let info = deviceInfo(id) else { continue }
            devices.append(info)
        }
        return devices
    }

    public static func deviceInfo(_ id: AudioDeviceID) -> AudioDeviceInfo? {
        // 输出通道数
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &streamCount) == noErr,
              streamCount > 0 else { return nil }

        guard let name: String = getString(id, kAudioObjectPropertyName) else { return nil }
        let uid = getString(id, kAudioDevicePropertyDeviceUID) ?? String(name.hashValue)
        let transport: UInt32 = getPropertyData(id, kAudioDevicePropertyTransportType) ?? 0
        let rate: Double = getPropertyData(id, kAudioDevicePropertyNominalSampleRate) ?? 0
        return AudioDeviceInfo(id: id, uid: uid, name: name,
                               isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
                               currentRate: rate, hasOutput: true)
    }

    static func getString(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<CFString>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return nil }
        let cfString = buffer.assumingMemoryBound(to: CFString.self).pointee
        return cfString as String
    }

    public static func defaultOutputDevice() -> AudioDeviceInfo? {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr else { return nil }
        return deviceInfo(id)
    }

    /// 优先选择内置 3.5mm 耳机孔(插入耳机时出现的"外置耳机"设备), 其次内置扬声器。
    /// 按 ID 反查设备 UID(用于身份校验: 拔出后 ID 可能被回收复用)。
    public static func uid(for id: AudioDeviceID) -> String? {
        getString(id, kAudioDevicePropertyDeviceUID)
    }

    public static func preferredOutput() -> AudioDeviceInfo? {
        let devices = allDevices()
        let jack = devices.first {
            $0.isBuiltIn && ($0.name.contains("外置耳机") || $0.name.lowercased().contains("external headphone"))
        }
        if let jack { return jack }
        let builtin = devices.filter { $0.isBuiltIn }
        if let speakers = builtin.first(where: { $0.name.contains("扬声器") || $0.name.lowercased().contains("speaker") }) {
            return speakers
        }
        return builtin.first ?? defaultOutputDevice()
    }

    // MARK: - Hog Mode(独占)

    /// 获取当前占用设备的进程 id, 0 表示无人占用, -1 表示自己占用。
    public static func hogOwner(_ device: AudioDeviceID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return -2 }
        var pid: pid_t = -2
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &pid) == noErr else { return -2 }
        return pid
    }

    /// 请求独占设备。成功返回 true。
    public static func takeHog(_ device: AudioDeviceID) -> Bool {
        let owner = hogOwner(device)
        if owner == getpid() { return true }
        if owner > 0 { return false }   // 已被其他进程占用, 不抢
        let status = setPropertyData(device, kAudioDevicePropertyHogMode, value: getpid())
        return status == noErr
    }

    public static func releaseHog(_ device: AudioDeviceID) {
        if hogOwner(device) == getpid() {
            _ = setPropertyData(device, kAudioDevicePropertyHogMode, value: pid_t(-1))
        }
    }

    // MARK: - 采样率

    @discardableResult
    public static func setNominalSampleRate(_ device: AudioDeviceID, _ rate: Double) -> Bool {
        let status = setPropertyData(device, kAudioDevicePropertyNominalSampleRate, value: rate)
        if status != noErr { return false }
        // 等待设备真正切换完成(属性是异步生效的)。
        for _ in 0..<50 {
            if let current: Double = getPropertyData(device, kAudioDevicePropertyNominalSampleRate),
               current == rate {
                return true
            }
            usleep(20_000)
        }
        return false
    }

    public static func nominalSampleRate(_ device: AudioDeviceID) -> Double {
        getPropertyData(device, kAudioDevicePropertyNominalSampleRate) ?? 0
    }

    private final class ListenerBox {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
    }

    /// 监听音频设备列表/默认输出变化(插拔耳机等)。返回是否成功。
    @discardableResult
    public static func startDeviceHotplugListener(_ handler: @escaping () -> Void) -> Bool {
        let box = ListenerBox(handler)
        listeners.append(box)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
            { _, _, _, client in
                guard let client else { return noErr }
                let box = Unmanaged<ListenerBox>.fromOpaque(client).takeUnretainedValue()
                box.handler()
                return noErr
            }, Unmanaged.passUnretained(box).toOpaque())
        return status == noErr
    }

    private static var listeners: [ListenerBox] = []

    /// 首个输出流的物理格式(内置设备通常为 32-bit float 2ch)。
    public static func physicalFormat(_ device: AudioDeviceID) -> AudioStreamBasicDescription? {
        // 1. 取设备的首个输出流 id
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamID: AudioStreamID = 0
        var streamSize = UInt32(MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &streamsAddress, 0, nil,
                                         &streamSize, &streamID) == noErr else { return nil }
        // 2. 取该流的物理格式
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(streamID, &formatAddress, 0, nil,
                                         &formatSize, &format) == noErr else { return nil }
        return format
    }
}
