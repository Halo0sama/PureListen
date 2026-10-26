import Foundation
import Darwin
import Synchronization

/// 单生产者/单消费者无锁环形缓冲(实时音频 IOProc 安全)。
/// 使用手动分配内存与 acquire/release 原子计数，保证数据先于写指针发布。
final class RingBuffer {
    private let capacity: Int        // 容量(帧, 2 的幂)
    private let channels: Int
    private let strideBytes: Int     // 每帧字节数
    private let raw: UnsafeMutableRawPointer
    private let writeCount = Atomic<Int>(0)       // 累计写入帧数(仅解码线程写)
    private let readCount = Atomic<Int>(0)        // 累计读取帧数(仅 IOProc 写)

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
        let written = writeCount.load(ordering: .relaxed)
        let read = readCount.load(ordering: .acquiring)
        return max(0, min(capacity, capacity - (written &- read)))
    }
    var availableToRead: Int {
        let written = writeCount.load(ordering: .acquiring)
        let read = readCount.load(ordering: .relaxed)
        return max(0, min(capacity, written &- read))
    }

    /// 写入交错帧, 返回实际写入数。
    func write(_ input: UnsafePointer<Float32>, frames inputFrames: Int) -> Int {
        let written = writeCount.load(ordering: .relaxed)
        let read = readCount.load(ordering: .acquiring)
        let space = max(0, min(capacity, capacity - (written &- read)))
        let count = max(0, min(inputFrames, space))
        var done = 0
        while done < count {
            let pos = (written &+ done) & (capacity - 1)
            let chunk = min(count - done, capacity - pos)
            memcpy(raw + pos * strideBytes, input + done * channels, chunk * strideBytes)
            done += chunk
        }
        writeCount.store(written &+ count, ordering: .releasing)
        return count
    }

    /// 读取交错帧(不足补零), 返回真实帧数。
    func read(into output: UnsafeMutablePointer<Float32>, frames wanted: Int) -> Int {
        let read = readCount.load(ordering: .relaxed)
        let written = writeCount.load(ordering: .acquiring)
        let available = max(0, min(capacity, written &- read))
        let count = max(0, min(wanted, available))
        var done = 0
        while done < count {
            let pos = (read &+ done) & (capacity - 1)
            let chunk = min(count - done, capacity - pos)
            memcpy(output + done * channels, raw + pos * strideBytes, chunk * strideBytes)
            done += chunk
        }
        if count < wanted {
            memset(output + count * channels, 0, (wanted - count) * strideBytes)
        }
        readCount.store(read &+ count, ordering: .releasing)
        return count
    }

    func reset() {
        // 仅在生产者持有解码锁、消费者 IO 已停止时调用。
        writeCount.store(0, ordering: .relaxed)
        readCount.store(0, ordering: .relaxed)
    }
}
