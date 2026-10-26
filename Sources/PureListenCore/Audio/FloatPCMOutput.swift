import AudioToolbox
import Foundation

/// HAL 的 Float32 虚拟格式与解码/环形缓冲之间的边界，不读取设备物理整数样本。
struct FloatPCMOutput {
    let channels: Int
    let nonInterleaved: Bool
    let decoderFormat: AudioStreamBasicDescription

    init(virtualFormat: AudioStreamBasicDescription) throws {
        let planar = virtualFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(virtualFormat.mChannelsPerFrame)
        let sampleBytes = UInt32(MemoryLayout<Float32>.size)
        guard virtualFormat.mFormatID == kAudioFormatLinearPCM,
              virtualFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              virtualFormat.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              virtualFormat.mBitsPerChannel == 32,
              (1...32).contains(channels), virtualFormat.mSampleRate > 0,
              virtualFormat.mBytesPerFrame == sampleBytes * (planar ? 1 : UInt32(channels)) else {
            throw NSError(domain: "ExclusivePlayer", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "输出设备的回调格式不是受支持的 Float32 PCM，已停止输出"])
        }
        self.channels = channels
        nonInterleaved = planar
        decoderFormat = AudioStreamBasicDescription(
            mSampleRate: virtualFormat.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: sampleBytes * UInt32(channels), mFramesPerPacket: 1,
            mBytesPerFrame: sampleBytes * UInt32(channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
    }

    /// 无分配、无锁；缓冲布局不符时保持静音，绝不越界写入。
    func render(ring: RingBuffer, output: UnsafeMutablePointer<AudioBufferList>,
                scratch: UnsafeMutableBufferPointer<Float32>, gain: Float) -> (frames: Int, clamped: Int64) {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        let usedCount = nonInterleaved ? channels : 1
        let groupChannels = nonInterleaved ? 1 : channels
        var frames = Int.max
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard buffers.count >= usedCount else { return (0, 0) }
        for i in 0..<usedCount {
            guard buffers[i].mData != nil, Int(buffers[i].mNumberChannels) == groupChannels,
                  Int(buffers[i].mDataByteSize) % (groupChannels * MemoryLayout<Float32>.size) == 0 else { return (0, 0) }
            frames = min(frames, Int(buffers[i].mDataByteSize) / (groupChannels * MemoryLayout<Float32>.size))
        }
        guard frames > 0, frames <= scratch.count / channels, let samples = scratch.baseAddress else { return (0, 0) }
        let got = ring.read(into: samples, frames: frames)
        let safeGain = gain.isFinite ? min(max(gain, 0), 1) : 0
        var clamped: Int64 = 0
        for i in 0..<(frames * channels) {
            var sample = samples[i] * safeGain
            if !sample.isFinite { sample = 0; clamped += 1 }
            else if sample > 1 { sample = 1; clamped += 1 }
            else if sample < -1 { sample = -1; clamped += 1 }
            samples[i] = sample
        }
        if nonInterleaved {
            for channel in 0..<channels {
                let destination = buffers[channel].mData!.assumingMemoryBound(to: Float32.self)
                for frame in 0..<frames { destination[frame] = samples[frame * channels + channel] }
            }
        } else {
            memcpy(buffers[0].mData!, samples, frames * channels * MemoryLayout<Float32>.size)
        }
        return (got, clamped)
    }
}
