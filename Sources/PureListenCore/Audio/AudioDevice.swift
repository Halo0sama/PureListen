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
        let alive: UInt32? = getPropertyData(id, kAudioDevicePropertyDeviceIsAlive)
        guard alive == 1 else { return nil }
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

    /// 按 ID 反查设备 UID(用于身份校验: 拔出后 ID 可能被回收复用)。
    public static func uid(for id: AudioDeviceID) -> String? {
        getString(id, kAudioDevicePropertyDeviceUID)
    }

    public static func preferredOutput() -> AudioDeviceInfo? {
        preferredOutput(in: allDevices(), defaultID: defaultOutputDevice()?.id)
    }

    /// 同一快照内优先外置输出、耳机孔、扬声器；独占引起的系统默认输出变化不改变选择。
    public static func preferredOutput(in devices: [AudioDeviceInfo], defaultID: AudioDeviceID?, preferredUID: String? = nil) -> AudioDeviceInfo? {
        let outputs = devices.filter(\.hasOutput)
        let external = outputs.filter { !$0.isBuiltIn }
        if let device = external.first(where: { $0.uid == preferredUID })
            ?? external.first(where: { $0.id == defaultID }) ?? external.first { return device }
        if let jack = outputs.first(where: {
            $0.name.contains("外置耳机") || $0.name.lowercased().contains("headphone")
        }) { return jack }
        if let speakers = outputs.first(where: {
            $0.name.contains("扬声器") || $0.name.lowercased().contains("speaker")
        }) { return speakers }
        return outputs.first(where: { $0.id == defaultID }) ?? outputs.first
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

    /// 可撤销的主队列监听：列表变化，以及设备先失效、后从列表移除的阶段。
    public final class HotplugListener {
        private struct Registration {
            let token: UUID
            let object: AudioObjectID
            var address: AudioObjectPropertyAddress
            let block: AudioObjectPropertyListenerBlock
        }
        private var registrations: [Registration] = []
        private let handler: (AudioDeviceID?) -> Void
        private var stopped = false

        public init(_ handler: @escaping (AudioDeviceID?) -> Void) {
            self.handler = handler
            observe(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
            observeDevices()
        }

        private func observe(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(object, &address) else { return }
            let token = UUID()
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, !self.stopped,
                      self.registrations.contains(where: { $0.token == token }) else { return }
                if object == AudioObjectID(kAudioObjectSystemObject) { self.observeDevices() }
                self.handler(object == AudioObjectID(kAudioObjectSystemObject) ? nil : object)
            }
            if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
                registrations.append(Registration(token: token, object: object, address: address, block: block))
            }
        }

        private func observeDevices() {
            let current = Set(AudioDevice.allDevices().map(\.id))
            let removed = registrations.filter { $0.object != AudioObjectID(kAudioObjectSystemObject) && !current.contains($0.object) }
            for var registration in removed {
                AudioObjectRemovePropertyListenerBlock(registration.object, &registration.address, .main, registration.block)
            }
            registrations.removeAll { $0.object != AudioObjectID(kAudioObjectSystemObject) && !current.contains($0.object) }
            let observed = Set(registrations.map(\.object))
            for id in current where !observed.contains(id) {
                observe(id, kAudioDevicePropertyDeviceIsAlive)
                observe(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
            }
        }

        public func stop() {
            guard !stopped else { return }
            stopped = true
            for var registration in registrations {
                AudioObjectRemovePropertyListenerBlock(registration.object, &registration.address, .main, registration.block)
            }
            registrations = []
        }

        deinit { stop() }
    }

    /// IOProc 使用虚拟格式；物理格式只描述设备侧数据，不能作为回调缓冲格式。
    public static func virtualFormat(_ device: AudioDeviceID) -> AudioStreamBasicDescription? {
        streamFormat(device, selector: kAudioStreamPropertyVirtualFormat)
    }

    /// 首个输出流的设备物理格式，仅供诊断。
    public static func physicalFormat(_ device: AudioDeviceID) -> AudioStreamBasicDescription? {
        streamFormat(device, selector: kAudioStreamPropertyPhysicalFormat)
    }

    private static func streamFormat(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> AudioStreamBasicDescription? {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streamsAddress, 0, nil, &streamSize) == noErr,
              streamSize >= UInt32(MemoryLayout<AudioStreamID>.size) else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(streamSize) / MemoryLayout<AudioStreamID>.size)
        let status = streams.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &streamsAddress, 0, nil, &streamSize, $0.baseAddress!)
        }
        guard status == noErr, let streamID = streams.first else { return nil }
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(streamID, &formatAddress, 0, nil,
                                         &formatSize, &format) == noErr else { return nil }
        return format
    }
}
