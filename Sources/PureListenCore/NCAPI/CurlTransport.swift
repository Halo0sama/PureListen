import Foundation

/// curl 传输集中处理代理、退出码、取消和临时文件；不记录 Cookie 或请求正文。
enum CurlTransport {
    struct Response {
        var data: Data
        var headers: String
        var statusCode: Int
        var effectiveURL: String
    }

    private static let queue = DispatchQueue(label: "PureListen.curl", attributes: .concurrent)

    private final class RequestProcess: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func launch(_ process: Process) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { throw CancellationError() }
            try process.run()
            self.process = process
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }

        func checkCancellation() throws {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { throw CancellationError() }
        }
    }

    static func request(method: String = "GET", url: String, headers: [String: String] = [:],
                        body: String? = nil, timeout: Int = 30, followRedirects: Bool = true,
                        mode: NetworkMode = .current) async throws -> Response {
        guard let source = URL(string: url), let host = source.host, !host.isEmpty,
              ["http", "https"].contains(source.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PureListen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let headerFile = directory.appendingPathComponent("headers")
        let dataFile = directory.appendingPathComponent("data")
        let bodyFile = directory.appendingPathComponent("body")
        if let body { try body.write(to: bodyFile, atomically: true, encoding: .utf8) }
        var args = ["--disable", "-s", "--compressed", "--max-time", String(max(1, timeout)),
                    "--connect-timeout", String(min(10, max(1, timeout))),
                    "--proto", "=http,https", "--proto-redir", "=http,https",
                    "-D", headerFile.path, "-o", dataFile.path, "-w", "%{http_code}\n%{url_effective}"]
        args += try mode.curlArguments(for: source)
        if followRedirects { args += ["-L", "--max-redirs", "8"] }
        if ProcessInfo.processInfo.environment["NC_FORCE_HTTP11"] != nil { args.append("--http1.1") }
        for (name, value) in headers { args += ["-H", "\(name): \(value)"] }
        if body != nil { args += ["--data-binary", "@\(bodyFile.path)"] }
        if method != "GET" { args += ["-X", method] }
        args += ["--url", url]

        let running = RequestProcess()
        let response: Response = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                        process.arguments = args
                        let output = Pipe()
                        process.standardOutput = output
                        process.standardError = FileHandle.nullDevice
                        try running.launch(process)
                        // 持续读管道，再等进程退出，避免写端堵塞。
                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        try running.checkCancellation()
                        guard process.terminationStatus == 0 else {
                            let code: URLError.Code
                            switch process.terminationStatus {
                            case 5, 6: code = .cannotFindHost
                            case 7: code = .cannotConnectToHost
                            case 28: code = .timedOut
                            case 35, 60: code = .secureConnectionFailed
                            default: code = .networkConnectionLost
                            }
                            throw URLError(code)
                        }
                        let fields = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n", maxSplits: 1)
                        let status = fields.first.flatMap { Int($0) } ?? 0
                        guard (200..<400).contains(status) else {
                            throw NSError(domain: "PureListen.HTTP", code: status,
                                          userInfo: [NSLocalizedDescriptionKey: "服务器返回 HTTP \(status)"])
                        }
                        continuation.resume(returning: Response(
                            data: try Data(contentsOf: dataFile),
                            headers: try String(contentsOf: headerFile, encoding: .utf8),
                            statusCode: status,
                            effectiveURL: fields.count > 1 ? String(fields[1]) : url))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { running.cancel() })
        try Task.checkCancellation()
        return response
    }
}
