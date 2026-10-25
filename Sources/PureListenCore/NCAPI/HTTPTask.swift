import Foundation

/// 通用 curl 传输(网易/B站 API 通用)。
/// 统一走 curl: 与 CFNetwork 不同指纹, 规避部分风控; 支持收集 Set-Cookie。
public enum HTTPTask {
    public struct Response {
        public var json: [String: Any]
        public var setCookies: [String: String]
        public var statusCode: Int
    }

    static let queue = DispatchQueue(label: "PureListen.httptask")

    public static func get(url: String, headers: [String: String] = [:],
                           timeout: Int = 20, followRedirects: Bool = true) async throws -> Response {
        try await request(method: "GET", url: url, headers: headers, body: nil,
                          timeout: timeout, followRedirects: followRedirects)
    }

    public static func post(url: String, headers: [String: String] = [:],
                            body: String? = nil, timeout: Int = 20) async throws -> Response {
        try await request(method: "POST", url: url, headers: headers, body: body,
                          timeout: timeout, followRedirects: true)
    }

    private static func request(method: String, url: String, headers: [String: String],
                                body: String?, timeout: Int,
                                followRedirects: Bool = true) async throws -> Response {
        let tmp = NSTemporaryDirectory() + UUID().uuidString
        let headerFile = tmp + ".h", dataFile = tmp + ".d", bodyFile = tmp + ".b"
        defer {
            for f in [headerFile, dataFile, bodyFile] { try? FileManager.default.removeItem(atPath: f) }
        }
        if let body { try body.write(toFile: bodyFile, atomically: true, encoding: .utf8) }

        var args = ["-s", "--compressed", "-m", String(timeout),
                    "-D", headerFile, "-o", dataFile, "-w", "%{http_code}"]
        if followRedirects { args.append("-L") }
        for (k, v) in headers { args += ["-H", "\(k): \(v)"] }
        if body != nil { args += ["--data-binary", "@\(bodyFile)"] }
        if method != "GET" { args += ["-X", method] }
        args.append(url)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = args
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = (process.standardOutput as? Pipe)?
                        .fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let code = Int(String(data: outData, encoding: .utf8) ?? "0") ?? 0
                    let rawHeaders = (try? String(contentsOfFile: headerFile, encoding: .utf8)) ?? ""
                    let data = (try? Data(contentsOf: URL(fileURLWithPath: dataFile))) ?? Data()

                    var cookies: [String: String] = [:]
                    for line in rawHeaders.split(separator: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.lowercased().hasPrefix("set-cookie:") else { continue }
                        let pair = String(trimmed.dropFirst("set-cookie:".count))
                        let nameValue = pair.split(separator: ";", maxSplits: 1).first.map(String.init) ?? pair
                        if let eq = nameValue.firstIndex(of: "=") {
                            let name = String(nameValue[..<eq]).trimmingCharacters(in: .whitespaces)
                            let value = String(nameValue[nameValue.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty { cookies[name] = value }
                        }
                    }
                    var json: [String: Any] = [:]
                    if !data.isEmpty,
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        json = obj
                    }
                    continuation.resume(returning: Response(json: json, setCookies: cookies, statusCode: code))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// cookie 字典 → Cookie 头。
    public static func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }
}
