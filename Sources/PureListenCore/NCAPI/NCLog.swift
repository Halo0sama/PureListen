import Foundation

/// 简易文件日志: ~/Library/Logs/PureListen.log (超过 2MB 自动清空)。
public enum NCLog {
    static let path = NSHomeDirectory() + "/Library/Logs/PureListen.log"
    private static let maxSize: Int = 2_000_000
    private static let lock = NSLock()

    public static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        } else if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int,
                  size > maxSize {
            try? fm.removeItem(at: url)
            fm.createFile(atPath: path, contents: nil)
        }
        let line = "[\(Date())] \(message)\n"
        guard let fh = try? FileHandle(forWritingTo: url) else { return }
        defer { try? fh.close() }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: line.data(using: .utf8)!)
    }
}
