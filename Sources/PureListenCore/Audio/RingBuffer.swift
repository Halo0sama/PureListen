import Foundation
import Darwin

/// 单生产者/单消费者无锁环形缓冲(实时音频 IOProc 安全)。
/// 使用手动分配的原始内存与内存屏障, 保证"数据先于指针发布"。
final class RingBuffer {
    private let capacity: Int        // 容量(帧, 2 的幂)
    private let channels: Int
    private let strideBytes: Int     // 每帧字节数
    private let raw: UnsafeMutableRawPointer
    private var writeCount = 0       // 累计写入帧数(仅解码线程写)
    private var readCount = 0        // 累计读取帧数(仅 IOProc 写)

    init(frames: Int, channels: Int) {
        precondition(frames > 0 && (frames & (frames - 1)) == 0, "容量必须是 2 的幂")
        self.capacity = frames
        self.channels = channels
        self.strideBytes = channels * MemoryLayout<Float32>.size
        self.raw = UnsafeMutableRawPointer.allocate(byteCount: frames * strideBytes, alignment: 64)
        raw.initializeMemory(as: Float32.self, repeating: 0, count: frames * channels)
    }
    deinit { raw.deallocate() }

    var capacityFrames: Int { capacity }

    var availableToWrite: Int {
        // 读取 readCount(另一线程写)
        OSMemoryBarrier()
        return capacity - (writeCount - readCount)
    }
    var availableToRead: Int {
        OSMemoryBarrier()
        return writeCount - readCount
    }

    /// 写入交错帧, 返回实际写入数。
    func write(_ input: UnsafePointer<Float32>, frames inputFrames: Int) -> Int {
        let space = max(0, capacity - (writeCount - readCount))
        let count = max(0, min(inputFrames, space))
        var done = 0
        while done < count {
            let pos = (writeCount + done) & (capacity - 1)
            let chunk = min(count - done, capacity - pos)
            memcpy(raw + pos * strideBytes, input + done * channels, chunk * strideBytes)
            done += chunk
        }
        OSMemoryBarrier()        // 数据落地后才发布写指针
        writeCount &+= count
        return count
    }

    /// 读取交错帧(不足补零), 返回真实帧数。
    func read(into output: UnsafeMutablePointer<Float32>, frames wanted: Int) -> Int {
        OSMemoryBarrier()
        let available = max(0, writeCount - readCount)
        let count = max(0, min(wanted, available))
        var done = 0
        while done < count {
            let pos = (readCount + done) & (capacity - 1)
            let chunk = min(count - done, capacity - pos)
            memcpy(output + done * channels, raw + pos * strideBytes, chunk * strideBytes)
            done += chunk
        }
        if count < wanted {
            memset(output + count * channels, 0, (wanted - count) * strideBytes)
        }
        readCount &+= count
        return count
    }

    func reset() {
        writeCount = 0
        readCount = 0
        memset(raw, 0, capacity * strideBytes)
    }
}
