import Foundation
import CoreAudio
import AudioToolbox
import Synchronization

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
    private var activeDeviceID: AudioDeviceID = 0
    /// 调试：停止后读取实际写向设备的采样（音量后）；回调中只写预分配存储。
    public var ioDump: [Float32] { Array(ioDumpStorage.prefix(ioDumpCount)) }
    private var ioDumpStorage: [Float32] = []
    public var ioDumpEnabled = false
    public private(set) var decodeDump: [Float32] = []
    private var decodeDumpCount = 0
    private var ioDumpCount = 0
    private let ioDumpMaxFrames = 96000 * 3
    public var volume: Float = 1.0 {
        didSet { volume = volume.isFinite ? min(max(volume, 0), 1) : 0 }
    }
    /// 音量 1.0 时位完美(不做任何乘法)。
    public var bitPerfect: Bool { volume >= 1.0 }

    /// 安全防护: 累计被钳制的异常采样数(诊断用)。
    public private(set) var clampedSampleCount: Int64 = 0

    /// 播放期间接管其余输出设备: 其他 App 在所有设备上都无处发声, 从根源消除漏音。
    public var blockOtherOutputs = true
    private var hoggedOthers: [AudioDeviceID] = []
    /// 当前独占设备的 UID(身份校验: 拔出后设备 ID 会被系统回收复用, 旧 ID 可能指向别的设备)。
    private var activeDeviceUID: String?
    private var activeDeviceExists: Bool {
        activeDeviceID != 0 && activeDeviceUID != nil && AudioDevice.uid(for: activeDeviceID) == activeDeviceUID
    }

    private func hogOtherOutputs() {
        releaseOtherOutputs()
        guard blockOtherOutputs else { return }
        let others = AudioDevice.allDevices().filter { $0.id != activeDeviceID }
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

    /// 环形缓冲实时状态(供链路可视化): (可用帧, 容量帧)。
    public func ringStats() -> (available: Int, capacity: Int) {
        guard let ring else { return (0, 0) }
        return (ring.availableToRead, ring.capacityFrames)
    }

    private var ioProcID: AudioDeviceIOProcID?
    private var ring: RingBuffer?
    private var extFile: ExtAudioFileRef?
    private var decodeThread: Thread?
    private let stopDecode = Atomic<Bool>(true)
    private let framesPlayed = Atomic<Int64>(0)
    private var clientFormat = AudioStreamBasicDescription()
    private var outputPCM: FloatPCMOutput?
    private var renderScratch: UnsafeMutablePointer<Float32>?
    private let renderCapacityFrames = 8192
    private let decodeLock = NSLock()
    private var decodeFinished: DispatchGroup?
    private var reachedEOF = false
    private var finishNotified = false
    private var generation = UUID()

    public init() {}

    // MARK: - 生命周期

    public func shutdown() {
        stopPlayback()
    }

    /// 播放一个本地音频文件。控制操作需由同一线程串行调用（App 使用主线程）。
    public func playFile(url: URL, metadata: TrackStatus) {
        stopPlayback()
        activeDeviceID = deviceID
        activeDeviceUID = AudioDevice.uid(for: activeDeviceID)
        clampedSampleCount = 0
        startFadeIn()
        ioDumpStorage = []
        decodeDump = []
        ioDumpCount = 0
        decodeDumpCount = 0
        trackStatus = metadata
        onTrackChange?(trackStatus)

        guard activeDeviceID != 0 else {
            state = .error("未选择输出设备")
            return
        }

        do {
            try openAndStart(url: url)
            state = .playing
        } catch {
            stopPlayback()
            state = .error("播放失败: \(error.localizedDescription)")
        }
    }

    /// 暂停: 停止 IO 并释放独占, 系统默认输出自动回连该设备(其他 App 恢复发声)。
    public func pause() {
        guard state == .playing, let ioProcID else { return }
        AudioDeviceStop(activeDeviceID, ioProcID)
        AudioDeviceDestroyIOProcID(activeDeviceID, ioProcID)
        self.ioProcID = nil
        restoreOriginalRate()
        AudioDevice.releaseHog(activeDeviceID)
        releaseOtherOutputs()
        state = .paused
    }

    /// 恢复: 重新接管设备并续播(缓冲与解码位置保留)。
    public func resume() {
        guard state == .paused else { return }
        guard activeDeviceExists else {
            state = .error("设备已变更(耳机重新插入?), 请重新点播")
            return
        }
        guard AudioDevice.takeHog(activeDeviceID) else {
            state = .error("设备被其他程序占用, 片刻后再试")
            return
        }
        do {
            guard rememberAndSetRate(Double(trackStatus.deviceRate)),
                  let virtual = AudioDevice.virtualFormat(activeDeviceID),
                  Int(virtual.mChannelsPerFrame) == Int(clientFormat.mChannelsPerFrame) else {
                throw NSError(domain: "ExclusivePlayer", code: -5,
                              userInfo: [NSLocalizedDescriptionKey: "输出设备格式已变化，请重新播放"])
            }
            outputPCM = try FloatPCMOutput(virtualFormat: virtual)
            decodeLock.lock()
            finishNotified = false
            decodeLock.unlock()
            try startIO()
            state = .playing
        } catch {
            stopPlayback()
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
        let createStatus = AudioDeviceCreateIOProcID(activeDeviceID, Self.ioCallbackImpl, selfPtr, &ioProc)
        guard createStatus == noErr, let proc = ioProc else {
            throw NSError(domain: "ExclusivePlayer", code: Int(createStatus),
                          userInfo: [NSLocalizedDescriptionKey: "无法创建音频输出回调"])
        }
        startFadeIn()
        guard AudioDeviceStart(activeDeviceID, proc) == noErr else {
            AudioDeviceDestroyIOProcID(activeDeviceID, proc)
            throw NSError(domain: "ExclusivePlayer", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动音频设备(可能被其他 App 独占)"])
        }
        ioProcID = proc
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
            originalDeviceRate = AudioDevice.nominalSampleRate(activeDeviceID)
        }
        return AudioDevice.setNominalSampleRate(activeDeviceID, rate)
    }

    private func restoreOriginalRate() {
        guard originalDeviceRate != nil else { return }
        guard activeDeviceExists else {
            NCLog.log("[播放] ⚠ 设备已变更(ID 回收?), 跳过采样率恢复")
            originalDeviceRate = nil
            return
        }
        if let rate = originalDeviceRate, AudioDevice.hasProperty(activeDeviceID, kAudioDevicePropertyNominalSampleRate) {
            AudioDevice.setNominalSampleRate(activeDeviceID, rate)
            NCLog.log(String(format: "[播放] 已恢复设备原采样率 %.0f", rate))
        }
        originalDeviceRate = nil
    }

    /// 暂停 IO 后串行 seek，避免清空环形缓冲时与实时回调同时读写。
    public func seek(to seconds: Double) {
        guard seconds.isFinite, state == .playing || state == .paused, let extFile, let ring else { return }
        let target = min(max(seconds, 0), max(trackStatus.seconds - 0.001, 0))
        let runningProc = state == .playing ? ioProcID : nil
        if let runningProc { AudioDeviceStop(activeDeviceID, runningProc) }
        decodeLock.lock()
        let result = ExtAudioFileSeek(extFile, Int64(target * Double(trackStatus.fileRate)))
        if result == noErr {
            ring.reset()
            reachedEOF = false
            finishNotified = false
            framesPlayed.store(Int64(target * Double(trackStatus.deviceRate)), ordering: .relaxed)
            startFadeIn()
        }
        decodeLock.unlock()
        if let runningProc, AudioDeviceStart(activeDeviceID, runningProc) != noErr {
            stopPlayback()
            state = .error("跳转后无法恢复音频输出")
        }
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
        let hogged = AudioDevice.takeHog(activeDeviceID)
        trackStatus.exclusive = hogged
        guard hogged else {
            throw NSError(domain: "ExclusivePlayer", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "输出设备被其他程序占用，请稍后重试"])
        }

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
                targetRate = AudioDevice.nominalSampleRate(activeDeviceID)
            }
            trackStatus.resampled = Int(targetRate) != fileRate
        } else {
            trackStatus.resampled = false
        }
        trackStatus.deviceRate = Int(AudioDevice.nominalSampleRate(activeDeviceID))

        // 3. IOProc 必须使用虚拟格式。物理格式可能是 Int16，回调实际仍是 Float32。
        guard let virtual = AudioDevice.virtualFormat(activeDeviceID) else {
            throw NSError(domain: "ExclusivePlayer", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取设备回调格式"])
        }
        let output = try FloatPCMOutput(virtualFormat: virtual)
        outputPCM = output
        clientFormat = output.decoderFormat
        guard abs(clientFormat.mSampleRate - targetRate) < 1 else {
            throw NSError(domain: "ExclusivePlayer", code: -7,
                          userInfo: [NSLocalizedDescriptionKey: "输出设备采样率尚未切换完成"])
        }
        NCLog.log("[播放] IO 虚拟格式: \(Int(virtual.mSampleRate)) Hz / \(virtual.mBitsPerChannel) bit float / \(output.channels) ch / bytesPerFrame=\(virtual.mBytesPerFrame)")
        if let physical = AudioDevice.physicalFormat(activeDeviceID) {
            NCLog.log("[播放] 设备物理格式（仅诊断）: \(Int(physical.mSampleRate)) Hz / \(physical.mBitsPerChannel) bit / bytesPerFrame=\(physical.mBytesPerFrame)")
        }
        var decoder = clientFormat
        status = ExtAudioFileSetProperty(extFileRef, kExtAudioFileProperty_ClientDataFormat,
                                         size, &decoder)
        guard status == noErr else {
            throw NSError(domain: "ExclusivePlayer", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "无法设置 Float32 解码输出格式"])
        }

        // 4. 始终以交错 Float32 解码和缓冲；IO 阶段按虚拟格式分配声道。
        let channels = output.channels
        ring = RingBuffer(frames: 1 << 17, channels: channels)
        renderScratch = .allocate(capacity: renderCapacityFrames * channels)
        if ioDumpEnabled { ioDumpStorage = [Float32](repeating: 0, count: ioDumpMaxFrames * channels) }
        ring?.reset()
        framesPlayed.store(0, ordering: .relaxed)
        stopDecode.store(false, ordering: .releasing)

        reachedEOF = false
        finishNotified = false
        let currentGeneration = generation
        let finished = DispatchGroup()
        finished.enter()
        decodeFinished = finished
        let thread = Thread { [weak self] in
            defer { finished.leave() }
            self?.decodeLoop(generation: currentGeneration)
        }
        thread.name = "PureListen.decoder"
        thread.qualityOfService = .userInitiated
        decodeThread = thread
        thread.start()
        try startIO()
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

    private func decodeLoop(generation currentGeneration: UUID) {
        guard let extFile, let ring else { return }
        let chunkFrames = 8192
        let bytesPerFrame = Int(clientFormat.mBytesPerFrame)
        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = clientFormat.mChannelsPerFrame
        let heap = UnsafeMutableRawPointer.allocate(byteCount: chunkFrames * bytesPerFrame, alignment: 16)
        bufferList.mBuffers.mData = heap
        defer { heap.deallocate() }
        var lastPosition = -1.0

        while !stopDecode.load(ordering: .acquiring) {
            decodeLock.lock()
            var shouldFinish = false
            if !reachedEOF && ring.availableToWrite >= chunkFrames {
                var frames = UInt32(chunkFrames)
                bufferList.mBuffers.mDataByteSize = UInt32(chunkFrames * bytesPerFrame)
                let result = ExtAudioFileRead(extFile, &frames, &bufferList)
                if result != noErr || frames == 0 {
                    reachedEOF = true
                    if result != noErr { NCLog.log("[播放] 解码读取失败: OSStatus=\(result)") }
                } else {
                    let source = heap.assumingMemoryBound(to: Float32.self)
                    if ioDumpEnabled && decodeDumpCount < ioDumpMaxFrames {
                        let count = min(Int(frames), ioDumpMaxFrames - decodeDumpCount)
                        decodeDump.append(contentsOf: UnsafeBufferPointer(start: source, count: count * Int(clientFormat.mChannelsPerFrame)))
                        decodeDumpCount += count
                    }
                    _ = ring.write(source, frames: Int(frames))
                }
            }
            if reachedEOF && ring.availableToRead == 0 && !finishNotified {
                finishNotified = true
                shouldFinish = true
            }
            decodeLock.unlock()

            if shouldFinish {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration, self.state == .playing else { return }
                    self.decodeLock.lock()
                    let stillFinished = self.reachedEOF
                    self.decodeLock.unlock()
                    if stillFinished { self.onTrackFinished?() }
                }
            }
            let position = Double(framesPlayed.load(ordering: .relaxed)) / max(Double(trackStatus.deviceRate), 1)
            if abs(position - lastPosition) >= 0.05 {
                lastPosition = position
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.trackStatus.positionSeconds = position
                    self.onTrackChange?(self.trackStatus)
                }
            }
            usleep(5_000)
        }
    }

    // MARK: - 实时回调

    private func ioCallback(_ outputData: UnsafePointer<AudioBufferList>?) -> OSStatus {
        guard let outputData, let ring, let outputPCM, let renderScratch else { return noErr }
        let scratch = UnsafeMutableBufferPointer(start: renderScratch, count: renderCapacityFrames * outputPCM.channels)
        let result = outputPCM.render(ring: ring, output: UnsafeMutablePointer(mutating: outputData),
                                      scratch: scratch, gain: volume * safeGain())
        framesPlayed.wrappingAdd(Int64(result.frames), ordering: .relaxed)
        framesSinceFadeStart += Int64(result.frames)
        clampedSampleCount += result.clamped
        if ioDumpEnabled {
            let count = min(result.frames * outputPCM.channels, ioDumpStorage.count - ioDumpCount)
            if count > 0 {
                for index in 0..<count { ioDumpStorage[ioDumpCount + index] = renderScratch[index] }
                ioDumpCount += count
            }
        }
        return noErr
    }

    // MARK: - 停止

    private func stopPlayback() {
        generation = UUID()
        stopDecode.store(true, ordering: .releasing)
        if let ioProcID {
            AudioDeviceStop(activeDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(activeDeviceID, ioProcID)
            self.ioProcID = nil
        }
        // 解码线程退出后才释放文件和环形缓冲，不在超时后释放仍被使用的内存。
        decodeFinished?.wait()
        decodeFinished = nil
        decodeThread = nil
        if clampedSampleCount > 0 {
            NCLog.log("[播放] ⚠ 本次播放钳制了 \(clampedSampleCount) 个异常采样")
        }
        if let extFile { ExtAudioFileDispose(extFile); self.extFile = nil }
        renderScratch?.deallocate()
        renderScratch = nil
        outputPCM = nil
        ring = nil
        restoreOriginalRate()
        if activeDeviceExists { AudioDevice.releaseHog(activeDeviceID) }
        releaseOtherOutputs()
        activeDeviceID = 0
        activeDeviceUID = nil
        framesPlayed.store(0, ordering: .relaxed)
        trackStatus.positionSeconds = 0
    }
}
