import Foundation
import CoreAudio
import AudioToolbox

/// 独占输出播放引擎:
/// FLAC 本地解码(ExtAudioFile) → 无锁环形缓冲 → IOProc 直写设备(绕过系统混音器)。
/// 播放前将设备标称采样率切到音源真实采样率, 并以 hog mode 独占设备, 从根源消除 SRC。
public final class ExclusivePlayer {
    public struct TrackStatus {
        public var title: String = ""
        public var artist: String = ""
        public var fileRate: Int = 0          // 音源真实采样率
        public var fileBits: Int = 0          // 音源位深
        public var deviceRate: Int = 0        // 实际使用的设备采样率
        public var resampled: Bool = false    // 设备不支持原生采样率时降采样
        public var format: String = ""        // flac / mp3
        public var level: String = ""         // lossless / hires ...
        public var exclusive: Bool = false    // 是否成功独占
        public var seconds: Double = 0
        public var positionSeconds: Double = 0

        public init() {}
    }

    public enum State: Equatable {
        case idle
        case loading(String)   // 下载/缓冲进度描述
        case playing
        case paused
        case error(String)
    }

    // 回调(在后台线程触发, UI 需自行切主线程)。
    public var onStateChange: ((State) -> Void)?
    public var onTrackChange: ((TrackStatus) -> Void)?
    public var onTrackFinished: (() -> Void)?

    public private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    public private(set) var trackStatus = TrackStatus()

    public var deviceID: AudioDeviceID = 0
    /// 调试: 抓取 IOProc 实际写向设备的采样(音量前), 供静音诊断。
    public private(set) var ioDump: [Float32] = []
    public var ioDumpEnabled = false
    public private(set) var decodeDump: [Float32] = []
    private var decodeDumpCount = 0
    private var ioDumpCount = 0
    private let ioDumpMaxFrames = 96000 * 3
    public var volume: Float = 1.0 {
        didSet { volume = min(max(volume, 0), 1) }
    }
    /// 音量 1.0 时位完美(不做任何乘法)。
    public var bitPerfect: Bool { volume >= 1.0 }

    /// 安全防护: 累计被钳制的异常采样数(诊断用)。
    public private(set) var clampedSampleCount: Int64 = 0

    /// 软件音量只对浮点格式设备安全; 整型物理格式设备跳过音量乘法(整数位当浮点乘=噪音)。
    /// 播放期间接管其余输出设备: 其他 App 在所有设备上都无处发声, 从根源消除漏音。
    public var blockOtherOutputs = true
    private var hoggedOthers: [AudioDeviceID] = []
    /// 当前独占设备的 UID(身份校验: 拔出后设备 ID 会被系统回收复用, 旧 ID 可能指向别的设备)。
    private var activeDeviceUID: String?
    private var activeDeviceExists: Bool { AudioDevice.uid(for: deviceID) == activeDeviceUID }

    private func hogOtherOutputs() {
        releaseOtherOutputs()
        guard blockOtherOutputs else { return }
        let others = AudioDevice.allDevices().filter { $0.id != deviceID }
        var taken: [AudioDeviceID] = []
        for device in others {
            if AudioDevice.takeHog(device.id) {
                taken.append(device.id)
            } else {
                NCLog.log("[播放] ⚠ 接管失败: \(device.name) (占用者 pid=\(AudioDevice.hogOwner(device.id)))")
            }
        }
        hoggedOthers = taken
        NCLog.log("[播放] 其余输出设备接管: \(taken.count)/\(others.count) 个")
    }

    private func releaseOtherOutputs() {
        guard !hoggedOthers.isEmpty else { return }
        for id in hoggedOthers {
            AudioDevice.releaseHog(id)
        }
        hoggedOthers = []
        NCLog.log("[播放] 已释放其余输出设备")
    }

    private var volumeApplies = true

    /// 起播/seek 后的淡入帧数(15ms), 消除爆音。
    private var fadeInFrames: Int = 0
    private var framesSinceFadeStart: Int64 = 0

    private func startFadeIn() {
        fadeInFrames = max(Int(Double(trackStatus.deviceRate) * 0.015), 64)
        framesSinceFadeStart = 0
    }

    /// 淡入系数。
    private func safeGain() -> Float {
        if fadeInFrames > 0, framesSinceFadeStart < Int64(fadeInFrames) {
            return Float(Double(framesSinceFadeStart) / Double(fadeInFrames))
        }
        return 1
    }

    /// 输出保险: 非法值钳制(正常音频 |v|≤1, 永不触发, 位完美不受影响)。
    private func sanitizeOutput(_ p: UnsafeMutablePointer<Float32>, count: Int, gain: Float) {
        var clamped: Int64 = 0
        if gain >= 1 {
            for i in 0..<count {
                let v = p[i]
                if v.isNaN || v.isInfinite { p[i] = 0; clamped += 1 }
                else if v > 1 { p[i] = 1; clamped += 1 }
                else if v < -1 { p[i] = -1; clamped += 1 }
            }
        } else {
            for i in 0..<count {
                var v = p[i] * gain
                if v.isNaN || v.isInfinite { v = 0; clamped += 1 }
                else if v > 1 { v = 1; clamped += 1 }
                else if v < -1 { v = -1; clamped += 1 }
                p[i] = v
            }
        }
        if clamped > 0 { clampedSampleCount += clamped }
    }

    /// 环形缓冲实时状态(供链路可视化): (可用帧, 容量帧)。
    public func ringStats() -> (available: Int, capacity: Int) {
        guard let ring else { return (0, 0) }
        return (ring.availableToRead, ring.capacityFrames)
    }

    private var ioProcID: AudioDeviceIOProcID?
    private var ring: RingBuffer?
    private var extFile: ExtAudioFileRef?
    private var decodeThread: Thread?
    private var stopDecode = false
    private var framesPlayed: Int64 = 0
    private var clientFormat = AudioStreamBasicDescription()

    public init() {}

    // MARK: - 生命周期

    public func shutdown() {
        stopPlayback()
    }

    /// 播放一个本地音频文件(独占模式)。在任意线程调用。
    public func playFile(url: URL, metadata: TrackStatus) {
        activeDeviceUID = AudioDevice.uid(for: deviceID)
        stopPlayback()
        clampedSampleCount = 0
        startFadeIn()
        ioDump = []
        decodeDump = []
        ioDumpCount = 0
        decodeDumpCount = 0
        trackStatus = metadata
        onTrackChange?(trackStatus)

        guard deviceID != 0 else {
            state = .error("未选择输出设备")
            return
        }

        do {
            try openAndStart(url: url)
            state = .playing
        } catch {
            state = .error("播放失败: \(error.localizedDescription)")
        }
    }

    /// 暂停: 停止 IO 并释放独占, 系统默认输出自动回连该设备(其他 App 恢复发声)。
    public func pause() {
        guard state == .playing, let ioProcID else { return }
        AudioDeviceStop(deviceID, ioProcID)
        AudioDeviceDestroyIOProcID(deviceID, ioProcID)
        self.ioProcID = nil
        AudioDevice.releaseHog(deviceID)
        releaseOtherOutputs()
        restoreOriginalRate()
        state = .paused
    }

    /// 恢复: 重新接管设备并续播(缓冲与解码位置保留)。
    public func resume() {
        guard state == .paused else { return }
        guard activeDeviceExists else {
            state = .error("设备已变更(耳机重新插入?), 请重新点播")
            return
        }
        guard AudioDevice.takeHog(deviceID) else {
            state = .error("设备被其他程序占用, 片刻后再试")
            return
        }
        if trackStatus.fileRate > 0 {
            rememberAndSetRate(Double(trackStatus.fileRate))
        }
        do {
            try startIO()
            state = .playing
        } catch {
            state = .error("恢复播放失败: \(error.localizedDescription)")
        }
    }

    private static let ioCallbackImpl: AudioDeviceIOProc = { device, now, inputData, inputTime,
        outputData, outputTime, client in
        guard let client else { return noErr }
        let player = Unmanaged<ExclusivePlayer>.fromOpaque(client).takeUnretainedValue()
        return player.ioCallback(outputData)
    }

    private func startIO() throws {
        var ioProc: AudioDeviceIOProcID?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let createStatus = AudioDeviceCreateIOProcID(deviceID, Self.ioCallbackImpl, selfPtr, &ioProc)
        guard createStatus == noErr, let proc = ioProc else {
            throw NSError(domain: "ExclusivePlayer", code: Int(createStatus),
                          userInfo: [NSLocalizedDescriptionKey: "无法创建音频输出回调"])
        }
        guard AudioDeviceStart(deviceID, proc) == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, proc)
            throw NSError(domain: "ExclusivePlayer", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动音频设备(可能被其他 App 独占)"])
        }
        ioProcID = proc
        startFadeIn()   // 恢复播放淡入, 防爆音
        hogOtherOutputs()   // 同时接管其余输出设备, 其他 App 全静默
    }

    public func stop() {
        stopPlayback()
        state = .idle
    }

    // MARK: - 进度拖动

    /// 被我们改采样率前设备的原采样率(独占结束时恢复, 不把设备留给系统一个乱七八糟的状态)。
    private var originalDeviceRate: Double?

    @discardableResult
    private func rememberAndSetRate(_ rate: Double) -> Bool {
        guard activeDeviceExists else {
            NCLog.log("[播放] ⚠ 设备已变更(ID 回收?), 跳过采样率设置")
            return false
        }
        if originalDeviceRate == nil {
            originalDeviceRate = AudioDevice.nominalSampleRate(deviceID)
        }
        return AudioDevice.setNominalSampleRate(deviceID, rate)
    }

    private func restoreOriginalRate() {
        guard activeDeviceExists else {
            NCLog.log("[播放] ⚠ 设备已变更(ID 回收?), 跳过采样率恢复")
            originalDeviceRate = nil
            return
        }
        if let rate = originalDeviceRate, AudioDevice.hasProperty(deviceID, kAudioDevicePropertyNominalSampleRate) {
            AudioDevice.setNominalSampleRate(deviceID, rate)
            NCLog.log(String(format: "[播放] 已恢复设备原采样率 %.0f", rate))
        }
        originalDeviceRate = nil
    }

    private var pendingSeekSeconds: Double?
    private var seeking = false

    /// 拖动进度(seek 由解码线程执行, 保证与 IOProc 不冲突)。
    public func seek(to seconds: Double) {
        guard case .playing = state else { return }
        pendingSeekSeconds = seconds
    }

    public var durationSeconds: Double { trackStatus.seconds }

    // MARK: - 核心流程

    private func openAndStart(url: URL) throws {
        // 1. 打开文件并读取真实格式
        var file: ExtAudioFileRef?
        let openStatus = ExtAudioFileOpenURL(url as CFURL, &file)
        guard openStatus == noErr, let extFileRef = file else {
            throw NSError(domain: "ExclusivePlayer", code: Int(openStatus),
                          userInfo: [NSLocalizedDescriptionKey: "无法打开音频文件"])
        }
        extFile = extFileRef

        var fileFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = ExtAudioFileGetProperty(extFileRef,
                                             kExtAudioFileProperty_FileDataFormat,
                                             &size, &fileFormat)
        guard status == noErr else {
            throw NSError(domain: "ExclusivePlayer", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "无法读取音频格式"])
        }

        var fileRate = Int(fileFormat.mSampleRate)
        var fileBits = Int(fileFormat.mBitsPerChannel)
        // FLAC 在 FileDataFormat 里报占位值(0bit), 手动读 STREAMINFO 拿真实位深
        if fileBits == 0, let flac = Self.parseFLACStreamInfo(url) {
            fileBits = flac.bitsPerSample
            if fileRate == 0 { fileRate = flac.sampleRate }
        }
        trackStatus.fileRate = fileRate
        trackStatus.fileBits = fileBits
        trackStatus.seconds = totalSeconds(extFileRef, rate: fileRate)
        NCLog.log(String(format: "[播放] 音源格式: %d Hz / %d bit / %d ch (文件头真实值)",
                         fileRate, fileBits, Int(fileFormat.mChannelsPerFrame)))

        // 2. 独占设备 + 把设备采样率切到与音源一致
        let hogged = AudioDevice.takeHog(deviceID)
        trackStatus.exclusive = hogged

        var targetRate = Double(fileRate)
        if !rememberAndSetRate(targetRate) {
            // 设备不支持该采样率: 内置孔上限 96k, 逐级回退到常见采样率。
            let fallbacks: [Double] = [96000, 88200, 48000, 44100]
            var ok = false
            for candidate in fallbacks where candidate < targetRate {
                if rememberAndSetRate(candidate) {
                    targetRate = candidate
                    ok = true
                    break
                }
            }
            if !ok {
                targetRate = AudioDevice.nominalSampleRate(deviceID)
            }
            trackStatus.resampled = Int(targetRate) != fileRate
        } else {
            trackStatus.resampled = false
        }
        trackStatus.deviceRate = Int(AudioDevice.nominalSampleRate(deviceID))

        // 3. 设备物理格式作为 client 格式(int→float 或 int 直通, 均无损)
        guard var physical = AudioDevice.physicalFormat(deviceID) else {
            NCLog.log("[播放] ✗ 无法读取设备物理格式")
            throw NSError(domain: "ExclusivePlayer", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取设备物理格式"])
        }
        physical.mSampleRate = targetRate
        clientFormat = physical
        NCLog.log(String(format: "[播放] 设备物理格式: %d Hz / %d bit / %d ch / flags=0x%X interleaved=%@ bytesPerFrame=%d",
                         Int(physical.mSampleRate), Int(physical.mBitsPerChannel),
                         Int(physical.mChannelsPerFrame), physical.mFormatFlags,
                         (physical.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0 ? "是" : "否",
                         Int(physical.mBytesPerFrame)))
        volumeApplies = (physical.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if !volumeApplies {
            NCLog.log("[播放] 设备为整型物理格式, 软件音量禁用(防止整数位被浮点乘出噪音)")
        }
        NCLog.log(String(format: "[播放] 独占=%@ 音源→设备采样率 %d → %d", hogged ? "成功" : "失败", fileRate, Int(targetRate)))
        status = ExtAudioFileSetProperty(extFileRef, kExtAudioFileProperty_ClientDataFormat,
                                         size, &physical)
        guard status == noErr else {
            throw NSError(domain: "ExclusivePlayer", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "无法设置解码输出格式"])
        }

        // 4. 环形缓冲 + 解码线程
        let channels = Int(physical.mChannelsPerFrame)
        ring = RingBuffer(frames: 1 << 17, channels: channels)   // ~1.5s @ 44.1k
        ring?.reset()
        framesPlayed = 0
        stopDecode = false

        let thread = Thread { [weak self] in self?.decodeLoop() }
        thread.name = "PureListen.decoder"
        thread.qualityOfService = .userInitiated
        thread.start()
        decodeThread = thread

        // 5. IOProc
        var ioProc: AudioDeviceIOProcID?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let createStatus = AudioDeviceCreateIOProcID(deviceID, { device, now, inputData, inputTime,
                                                                 outputData, outputTime, client in
            let player = Unmanaged<ExclusivePlayer>.fromOpaque(client!).takeUnretainedValue()
            return player.ioCallback(outputData)
        }, selfPtr, &ioProc)
        guard createStatus == noErr, let proc = ioProc else {
            stopDecode = true
            throw NSError(domain: "ExclusivePlayer", code: Int(createStatus),
                          userInfo: [NSLocalizedDescriptionKey: "无法创建音频输出回调"])
        }
        ioProcID = proc
        guard AudioDeviceStart(deviceID, proc) == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, proc)
            ioProcID = nil
            stopDecode = true
            throw NSError(domain: "ExclusivePlayer", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动音频设备(可能被其他 App 独占)"])
        }
        hogOtherOutputs()   // 同时接管其余输出设备(修复: 此前漏插在主播放路径)
        onTrackChange?(trackStatus)
    }


    struct FLACStreamInfo {
        var sampleRate: Int
        var channels: Int
        var bitsPerSample: Int
    }

    /// 解析 FLAC 头部 STREAMINFO(偏移 8 起的 34 字节)。
    static func parseFLACStreamInfo(_ url: URL) -> FLACStreamInfo? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 42), head.count >= 26,
              head[0] == 0x66, head[1] == 0x4C, head[2] == 0x61, head[3] == 0x43 else { return nil }  // "fLaC"
        let b = [UInt8](head)
        let packed1 = (UInt32(b[18]) << 16) | (UInt32(b[19]) << 8) | UInt32(b[20])
        let sampleRate = Int(packed1 >> 4)
        let channels = Int((packed1 >> 1) & 0x7) + 1
        let bits = Int(((packed1 & 0x1) << 4) | (UInt32(b[21]) >> 4)) + 1
        guard sampleRate > 0, (1...8).contains(channels), (4...32).contains(bits) else { return nil }
        return FLACStreamInfo(sampleRate: sampleRate, channels: channels, bitsPerSample: bits)
    }

    private func totalSeconds(_ file: ExtAudioFileRef, rate: Int) -> Double {
        var length: Int64 = 0
        var size = UInt32(MemoryLayout<Int64>.size)
        guard ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames,
                                      &size, &length) == noErr, rate > 0 else { return 0 }
        return Double(length) / Double(rate)
    }

    // MARK: - 解码线程

    private func decodeLoop() {
        guard let extFile, let ring else { return }
        let chunkFrames = 8192
        let bytesPerFrame = Int(clientFormat.mBytesPerFrame)
        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = clientFormat.mChannelsPerFrame
        bufferList.mBuffers.mDataByteSize = UInt32(chunkFrames * bytesPerFrame)
        let heap = UnsafeMutableRawPointer.allocate(byteCount: chunkFrames * bytesPerFrame, alignment: 16)
        bufferList.mBuffers.mData = heap
        defer { heap.deallocate() }

        var eof = false
        while !stopDecode {
            if let target = pendingSeekSeconds, !seeking {
                seeking = true
                let frame = Int64(target * Double(trackStatus.fileRate))
                if ExtAudioFileSeek(extFile, frame) == noErr {
                    ring.reset()
                    framesPlayed = Int64(target * Double(trackStatus.deviceRate))
                    eof = false
                    startFadeIn()   // seek 后同样淡入防爆音
                }
                pendingSeekSeconds = nil
                seeking = false
            }
            if ring.availableToWrite >= chunkFrames {
                if eof {
                    // 播完: 等缓冲排空再通知
                    if ring.availableToRead == 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.onTrackFinished?()
                        }
                        return
                    }
                    usleep(20_000)
                    continue
                }
                var frames = UInt32(chunkFrames)
                let status = ExtAudioFileRead(extFile, &frames, &bufferList)
                if status != noErr || frames == 0 {
                    eof = true
                    continue
                }
                let src = bufferList.mBuffers.mData!.assumingMemoryBound(to: Float32.self)
                if ioDumpEnabled, decodeDumpCount < ioDumpMaxFrames {
                    decodeDump.append(contentsOf: UnsafeBufferPointer(start: src, count: Int(frames) * Int(clientFormat.mChannelsPerFrame)))
                    decodeDumpCount += Int(frames)
                }
                _ = ring.write(src, frames: Int(frames))
                // 单声道文件 mBytesPerFrame 情况: client 格式与设备一致, 通道匹配。
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.trackStatus.positionSeconds = Double(self.framesPlayed) /
                        max(Double(self.trackStatus.deviceRate), 1)
                    self.onTrackChange?(self.trackStatus)
                }
            } else {
                usleep(15_000)
            }
        }
    }

    private func p0Samples(_ p: UnsafePointer<Float32>, frames: Int, channels: Int) -> [Float32] {
        Array(UnsafeBufferPointer(start: p, count: frames * channels))
    }

    // MARK: - 实时回调

    private var loggedIOStructure = false

    private func ioCallback(_ outputData: UnsafePointer<AudioBufferList>?) -> OSStatus {
        guard let outputData else { return noErr }
        guard let ring else { return noErr }
        let list = UnsafeMutablePointer(mutating: outputData)
        let bufferCount = Int(list.pointee.mNumberBuffers)
        let channels = Int(clientFormat.mChannelsPerFrame)

        if !loggedIOStructure {
            loggedIOStructure = true
            var desc = "IOProc 缓冲列表: \(bufferCount) 个缓冲"
            for i in 0..<min(bufferCount, 4) {
                let b = list[i].mBuffers
                desc += " [\(i)] ch=\(b.mNumberChannels) bytes=\(b.mDataByteSize)"
            }
            NCLog.log("[播放] " + desc)
        }

        if bufferCount == 1, let data = list[0].mBuffers.mData {
            // 交错: 直接整块搬运
            let frames = Int(list[0].mBuffers.mDataByteSize) / max(Int(clientFormat.mBytesPerFrame), 1)
            let p = data.assumingMemoryBound(to: Float32.self)
            let got = ring.read(into: p, frames: frames)
            framesPlayed += Int64(got)
            framesSinceFadeStart += Int64(frames)
            if ioDumpEnabled, ioDumpCount < ioDumpMaxFrames {
                ioDump.append(contentsOf: UnsafeBufferPointer(start: p, count: frames * channels))
                ioDumpCount += frames
            }
            // 安全输出: 淡入 × 音量 × 非法值钳制(杜绝任何形式的爆音)
            let gain = (volumeApplies ? volume : 1) * safeGain()
            sanitizeOutput(p, count: frames * channels, gain: gain)
        } else if bufferCount >= 2, channels == 2 {
            // 非交错(每通道一个缓冲): 从交错的 ring 拆声道
            let first = list[0].mBuffers
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float32>.size
            guard let left = first.mData?.assumingMemoryBound(to: Float32.self),
                  let right = list[1].mBuffers.mData?.assumingMemoryBound(to: Float32.self) else {
                return noErr
            }
            scratchDeinterleave(with: frames)
            let got = ring.read(into: deinterleaveScratch, frames: frames)
            framesPlayed += Int64(got)
            framesSinceFadeStart += Int64(frames)
            sanitizeOutput(deinterleaveScratch, count: frames * 2,
                           gain: (volumeApplies ? volume : 1) * safeGain())
            for f in 0..<frames {
                left[f] = deinterleaveScratch[f * 2]
                right[f] = deinterleaveScratch[f * 2 + 1]
            }
            if ioDumpEnabled, ioDumpCount < ioDumpMaxFrames {
                ioDump.append(contentsOf: UnsafeBufferPointer(start: deinterleaveScratch, count: frames * channels))
                ioDumpCount += frames
            }
        }
        return noErr
    }

    private var deinterleaveScratch: UnsafeMutablePointer<Float32> = .allocate(capacity: 8192 * 2)
    private func scratchDeinterleave(with frames: Int) {
        if frames > 8192 {
            deinterleaveScratch.deallocate()
            deinterleaveScratch = .allocate(capacity: frames * 2)
        }
    }

    // MARK: - 停止

    private func stopPlayback() {
        if clampedSampleCount > 0 {
            NCLog.log("[播放] ⚠ 本次播放钳制了 \(clampedSampleCount) 个异常采样(数据异常已被安全拦截)")
        }
        stopDecode = true
        // 等解码线程退出后再释放资源, 避免 ExtAudioFileRead 访问已释放句柄(use-after-free)
        if let thread = decodeThread {
            let deadline = Date().addingTimeInterval(2.0)
            while thread.isExecuting && Date() < deadline {
                usleep(2000)
            }
            decodeThread = nil
        }
        if let ioProcID {
            AudioDeviceStop(deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            self.ioProcID = nil
        }
        if let extFile {
            ExtAudioFileDispose(extFile)
            self.extFile = nil
        }
        releaseOtherOutputs()
        ring = nil
        if deviceID != 0 {
            AudioDevice.releaseHog(deviceID)
            restoreOriginalRate()
        }
        framesPlayed = 0
        trackStatus.positionSeconds = 0
    }
}
