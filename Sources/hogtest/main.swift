import Foundation
import PureListenCore
import CoreAudio
import AudioToolbox

// hogtest: 在本机验证独占输出全链路。
// 生成一段 88.2kHz/16bit 的安静正弦波 WAV, 用 ExclusivePlayer 播放:
// 预期设备采样率 96000 → 88200, hog 被 hogtest 占用, 播放结束后恢复。

func writeWav(path: String, sampleRate: Int, seconds: Double, freq: Double, amp: Float) {
    let frames = Int(Double(sampleRate) * seconds)
    let bytesPerSample = 2
    let channels = 2
    var pcm = [Int16](repeating: 0, count: frames * channels)
    let fadeFrames = Int(Double(sampleRate) * 0.15)

    for i in 0..<frames {
        var envelope = amp
        if i < fadeFrames { envelope *= Float(i) / Float(fadeFrames) }
        if i > frames - fadeFrames { envelope *= Float(frames - i) / Float(fadeFrames) }
        let t = Double(i) / Double(sampleRate)
        let phase = 2.0 * Double.pi * freq * t
        let value = Double(envelope) * sin(phase)
        let int16 = Int16(max(-32768.0, min(32767.0, value * 32767.0)))
        pcm[i * channels] = int16
        pcm[i * channels + 1] = int16
    }

    var data = Data()
    func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
    func appendStr(_ s: String) { data.append(contentsOf: s.utf8) }

    appendStr("RIFF")
    append(UInt32(36 + pcm.count * bytesPerSample).littleEndian)
    appendStr("WAVE")
    appendStr("fmt ")
    append(UInt32(16).littleEndian)
    append(UInt16(1).littleEndian)                 // PCM
    append(UInt16(channels).littleEndian)
    append(UInt32(sampleRate).littleEndian)
    append(UInt32(sampleRate * channels * bytesPerSample).littleEndian)
    append(UInt16(channels * bytesPerSample).littleEndian)
    append(UInt16(16).littleEndian)
    appendStr("data")
    append(UInt32(pcm.count * bytesPerSample).littleEndian)
    pcm.withUnsafeBytes { data.append(contentsOf: $0) }

    try! data.write(to: URL(fileURLWithPath: path))
}

let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1] == "devices" {
    for device in AudioDevice.allDevices() {
        print("device=\(device.id) name=\(device.name) rate=\(device.currentRate)")
        if let v = AudioDevice.virtualFormat(device.id), let p = AudioDevice.physicalFormat(device.id) {
            print("  virtual: \(v.mBitsPerChannel)bit flags=\(v.mFormatFlags) bytesPerFrame=\(v.mBytesPerFrame); physical: \(p.mBitsPerChannel)bit flags=\(p.mFormatFlags) bytesPerFrame=\(p.mBytesPerFrame)")
        }
    }
    exit(0)
}
if arguments.count > 3, arguments[1] == "verify-silent" {
    guard let id = UInt32(arguments[3]), let device = AudioDevice.allDevices().first(where: { $0.id == id }) else {
        print("未找到指定设备"); exit(1)
    }
    let generated = arguments[2] == "--generated"
    let path = generated ? NSTemporaryDirectory() + "PureListen-\(UUID().uuidString).wav" : arguments[2]
    if generated { writeWav(path: path, sampleRate: 48000, seconds: 2, freq: 440, amp: 0.08) }
    defer { if generated { try? FileManager.default.removeItem(atPath: path) } }
    let originalRate = AudioDevice.nominalSampleRate(id)
    let player = ExclusivePlayer()
    player.deviceID = id
    player.volume = 0
    player.blockOtherOutputs = false
    player.ioDumpEnabled = true
    var finished = false
    player.onTrackFinished = { finished = true }
    player.onStateChange = { print("state=\($0)") }
    func pump(_ seconds: Double) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }
    var metadata = ExclusivePlayer.TrackStatus()
    metadata.title = "静音链路验证"
    metadata.format = URL(fileURLWithPath: path).pathExtension
    print("设备: \(device.name)，音量=0，不接管其他输出设备")
    player.playFile(url: URL(fileURLWithPath: path), metadata: metadata)
    var ok = player.state == .playing && AudioDevice.hogOwner(id) == getpid()
    pump(0.25)
    player.pause()
    ok = ok && player.state == .paused && AudioDevice.nominalSampleRate(id) == originalRate
    player.resume()
    ok = ok && player.state == .playing
    player.seek(to: 0.1)
    pump(0.2)
    // 连续重启覆盖旧 IO、文件释放和仍在启动的解码线程。
    player.playFile(url: URL(fileURLWithPath: path), metadata: metadata)
    player.playFile(url: URL(fileURLWithPath: path), metadata: metadata)
    pump(0.25)
    ok = ok && player.state == .playing
    let duration = player.durationSeconds
    finished = false
    player.seek(to: max(0, duration - 0.15))
    pump(0.5)
    ok = ok && finished
    let clamped = player.clampedSampleCount
    player.shutdown()
    let decoded = player.decodeDump
    let output = player.ioDump
    let decodeValid = !decoded.isEmpty && decoded.allSatisfy { $0.isFinite && abs($0) <= 1 }
    let decodeNonzero = decoded.contains { abs($0) > 0.000001 }
    let outputSilent = !output.isEmpty && output.allSatisfy { $0 == 0 }
    let restored = AudioDevice.nominalSampleRate(id) == originalRate && AudioDevice.hogOwner(id) != getpid()
    print("decodedSamples=\(decoded.count) finiteInRange=\(decodeValid) nonzero=\(decodeNonzero)")
    print("outputSamples=\(output.count) allZero=\(outputSilent) clamped=\(clamped)")
    print("finished=\(finished) rateRestored=\(restored)")
    let passed = ok && decodeValid && decodeNonzero && outputSilent && clamped == 0 && restored
    print(passed ? "PASS: 静音硬件链路验证通过" : "FAIL: 静音硬件链路验证失败")
    exit(passed ? 0 : 1)
}
if arguments.count > 1, arguments[1] == "voltest" {
    // hog 独占下, 系统音量属性是否仍可变(coreaudiod 是否被 hog 挡住)
    guard let device = AudioDevice.preferredOutput() else { print("无设备"); exit(1) }
    print("设备: \(device.name) id=\(device.id)")
    let gotHog = AudioDevice.takeHog(device.id)
    print("hog: \(gotHog ? "成功" : "失败")")
    Thread.sleep(forTimeInterval: 0.5)
    print("→ 现在用 osascript 把系统音量设为 30%…")
    let p1 = Process()
    p1.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p1.arguments = ["-e", "set volume output volume 30"]
    try? p1.run(); p1.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.8)
    // 读 VolumeScalar
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput, mElement: 1)
    var vol: Float32 = -1
    var size = UInt32(MemoryLayout<Float32>.size)
    let st = AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &vol)
    print("VolumeScalar(ch1) = \(vol) (status=\(st))")
    var addrM = addr; addrM.mElement = 0
    var volM: Float32 = -1
    let stM = AudioObjectGetPropertyData(device.id, &addrM, 0, nil, &size, &volM)
    print("VolumeScalar(master el0) = \(volM) (status=\(stM))")

    // VirtualMasterVolume: coreaudiod 维护, 音量键/Sound 滑块改的就是它
    // 系统音量百分比(AppleScript)在 hog 下是否仍可读写
    func sysVol() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "output volume of (get volume settings)"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return Int(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "") ?? -1
    }
    print("hog 下初始系统音量: \(sysVol())%")
    for target in [80, 20, 50] {
        let set = Process()
        set.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        set.arguments = ["-e", "set volume output volume \(target)"]
        try? set.run(); set.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.5)
        print("设 \(target)% → 读回 \(sysVol())%")
    }
    AudioDevice.releaseHog(device.id)
    exit(0)
}

if arguments.count > 2, arguments[1] == "playdump" {
    // 全管线静音播放: 抓 IOProc 喂给设备的真实数据
    let path = arguments[2]
    let vol = arguments.count > 3 ? Float(arguments[3]) ?? 0 : 0
    guard let device = AudioDevice.preferredOutput() else { print("无输出设备"); exit(1) }
    print(String(format: "设备: %@ (id=%d) 当前采样率 %.0f → 静音(音量 %.2f)全管线播放", device.name, device.id, device.currentRate, vol))
    let player = ExclusivePlayer()
    player.deviceID = device.id
    player.volume = vol
    player.ioDumpEnabled = true
    var st = ExclusivePlayer.TrackStatus()
    st.title = "playdump"
    st.format = "flac"
    player.playFile(url: URL(fileURLWithPath: path), metadata: st)
    print(player.state)
    Thread.sleep(forTimeInterval: 6)
    player.shutdown()
    func stats(_ arr: [Float32], _ label: String) {
        guard !arr.isEmpty else { print("\(label): 无数据"); return }
        var rms = 0.0; var mn: Float = 10; var mx: Float = -10; var bad = 0; var huge = 0
        for v in arr {
            if v.isNaN || v.isInfinite { bad += 1; continue }
            if abs(v) > 1.0 { huge += 1 }
            rms += Double(v * v); mn = min(mn, v); mx = max(mx, v)
        }
        print(String(format: "%@: %d 采样 RMS=%.4f 范围=[%.4f, %.4f] NaN/Inf=%d |v|>1=%d 首8=%@",
                     label, arr.count, (rms / Double(arr.count)).squareRoot(), mn, mx, bad, huge,
                     arr.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: " ")))
    }
    stats(player.decodeDump, "解码侧(进ring前)")
    stats(player.ioDump, "IO侧(喂设备)")
    let d = player.decodeDump
    if !d.isEmpty {
        if let fh = FileManager.default.createFile(atPath: "/tmp/decodedump.f32", contents: nil) ? FileHandle(forWritingAtPath: "/tmp/decodedump.f32") : nil {
            d.withUnsafeBufferPointer { ptr in fh.write(Data(buffer: ptr)) }
            try? fh.close()
        }
    }
    let iod = player.ioDump
    if !iod.isEmpty {
        if let fh = FileManager.default.createFile(atPath: "/tmp/iodump.f32", contents: nil) ? FileHandle(forWritingAtPath: "/tmp/iodump.f32") : nil {
            iod.withUnsafeBufferPointer { ptr in fh.write(Data(buffer: ptr)) }
            try? fh.close()
        }
    }
    exit(0)
}
if arguments.count > 2, arguments[1] == "analyze" {
    // 离线解码分析: 用与 App 相同的 ExtAudioFile + client float32 路径
    let path = arguments[2]
    var file: ExtAudioFileRef?
    guard ExtAudioFileOpenURL(URL(fileURLWithPath: path) as CFURL, &file) == noErr, let extFile = file else {
        print("打开失败"); exit(1)
    }
    var fmt = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileDataFormat, &size, &fmt)
    print(String(format: "文件格式: %d Hz %d ch flags=0x%X", Int(fmt.mSampleRate), Int(fmt.mChannelsPerFrame), fmt.mFormatFlags))

    var client = AudioStreamBasicDescription(mSampleRate: fmt.mSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
        mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    guard ExtAudioFileSetProperty(extFile, kExtAudioFileProperty_ClientDataFormat,
                                  UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client) == noErr else {
        print("client 格式设置失败"); exit(1)
    }
    let chunk = 8192
    var bl = AudioBufferList()
    bl.mNumberBuffers = 1
    bl.mBuffers.mNumberChannels = 2
    bl.mBuffers.mDataByteSize = UInt32(chunk * 8)
    let heap = UnsafeMutableRawPointer.allocate(byteCount: chunk * 8, alignment: 16)
    bl.mBuffers.mData = heap
    defer { heap.deallocate() }

    var totalFrames = 0
    let skipFirst = arguments.count > 3 ? Int(arguments[3]) ?? 0 : 0
    var skipped = 0
    while skipped < skipFirst {
        var frames = UInt32(chunk)
        _ = ExtAudioFileRead(extFile, &frames, &bl)
        if frames == 0 { break }
        skipped += Int(frames)
    }
    if skipFirst > 0 { print("已跳过 \(skipped) 帧 (\(Double(skipped)/96_000.0) 秒)") }
    for chunkIndex in 0..<20 {
        var frames = UInt32(chunk)
        let status = ExtAudioFileRead(extFile, &frames, &bl)
        guard frames > 0 else { print("读取结束"); break }
        let p = heap.assumingMemoryBound(to: Float32.self)
        var minV: Float = 10, maxV: Float = -10, sum: Double = 0
        var nanCount = 0
        for i in 0..<Int(frames) * 2 {
            let v = p[i]
            if v.isNaN || v.isInfinite { nanCount += 1; continue }
            minV = min(minV, v); maxV = max(maxV, v); sum += Double(v * v)
        }
        let rms = (sum / Double(Int(frames) * 2)).squareRoot()
        if chunkIndex < 5 || chunkIndex % 5 == 0 {
            print(String(format: "块 %2d: %6d 帧 RMS=%.4f 范围=[%.3f, %.3f] 异常值=%d status=%d 前4采样=[%.4f %.4f %.4f %.4f]",
                         chunkIndex, frames, rms, minV, maxV, nanCount, status, p[0], p[1], p[2], p[3]))
        }
        totalFrames += Int(frames)
    }
    print("共解码 \(totalFrames) 帧 (\(Double(totalFrames)/96_000.0) 秒)")
    exit(0)
}
let useCustomFile = arguments.count > 1
let wavPath = useCustomFile ? arguments[1] : "/tmp/hogtest_88k.wav"
if !useCustomFile {
    writeWav(path: wavPath, sampleRate: 88200, seconds: 5, freq: 440, amp: 0.08)
}
print("播放文件: \(wavPath)")

print("== 输出设备列表 ==")
for d in AudioDevice.allDevices() {
    print(String(format: "  id=%d  %@  rate=%.0f  builtIn=%@", d.id, d.name, d.currentRate, d.isBuiltIn ? "是" : "否"))
}
guard let device = AudioDevice.preferredOutput() else {
    print("!! 未找到输出设备"); exit(1)
}
let originalRate = AudioDevice.nominalSampleRate(device.id)
print(String(format: "\n目标设备: %@ (id=%d), 原采样率 %.0f Hz", device.name, device.id, originalRate))

let player = ExclusivePlayer()
player.deviceID = device.id

let done = DispatchSemaphore(value: 0)
player.onTrackChange = { status in
    print(String(format: "  [音轨] %@  音源 %d Hz/%d bit → 设备 %d Hz  独占=%@  降采样=%@  进度 %.1fs",
                 status.title.isEmpty ? "hogtest 88.2kHz 正弦波" : status.title,
                 status.fileRate, status.fileBits, status.deviceRate,
                 status.exclusive ? "是" : "否", status.resampled ? "是" : "否", status.positionSeconds))
}
player.onStateChange = { state in
    print("  [状态] \(state)")
}
player.onTrackFinished = {
    print("  [完成] 播放结束")
    done.signal()
}

var status = ExclusivePlayer.TrackStatus()
status.title = "hogtest 88.2kHz 正弦波"
status.artist = "PureListen"
status.format = "wav"
status.level = "lossless"
player.playFile(url: URL(fileURLWithPath: wavPath), metadata: status)

let hogOwner = AudioDevice.hogOwner(device.id)
print(String(format: "\nhog 占用者 pid=%d (本进程 %d): %@", hogOwner, getpid(), hogOwner == getpid() ? "独占成功" : "未独占!"))
print(String(format: "设备采样率: %.0f Hz (原 %.0f Hz)", AudioDevice.nominalSampleRate(device.id), originalRate))

_ = done.wait(timeout: .now() + 12)
player.shutdown()

// 恢复现场
AudioDevice.setNominalSampleRate(device.id, originalRate)
let afterOwner = AudioDevice.hogOwner(device.id)
print(String(format: "\n结束后: hog=%@, 采样率已恢复 %.0f Hz",
             afterOwner == 0 ? "已释放" : "pid \(afterOwner)",
             AudioDevice.nominalSampleRate(device.id)))
print(hogOwner == getpid() && AudioDevice.nominalSampleRate(device.id) == originalRate
      ? "\n✅ 独占播放链路验证通过"
      : "\n❌ 验证未通过")
