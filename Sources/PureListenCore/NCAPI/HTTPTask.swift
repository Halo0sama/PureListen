import Foundation

/// 通用 curl 传输(网易/B站 API 通用)。
/// 统一走 curl: 与 CFNetwork 不同指纹, 规避部分风控; 支持收集 Set-Cookie。
public enum HTTPTask {
    public struct Response {
        public var json: [String: Any]
        public var setCookies: [String: String]
        public var statusCode: Int
    }

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
        let response = try await CurlTransport.request(method: method, url: url, headers: headers,
                                                       body: body, timeout: timeout,
                                                       followRedirects: followRedirects)
        var cookies: [String: String] = [:]
        for line in response.headers.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("set-cookie:") else { continue }
            let pair = trimmed.dropFirst("set-cookie:".count).split(separator: ";", maxSplits: 1).first ?? ""
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = pair[..<eq].trimmingCharacters(in: .whitespaces)
            let value = pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { cookies[name] = value }
        }
        let json = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any] ?? [:]
        return Response(json: json, setCookies: cookies, statusCode: response.statusCode)
    }

    /// cookie 字典 → Cookie 头。
    public static func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }
}
