import Foundation
import CFNetwork

/// API 与音频下载共用的网络策略。Finder 启动的 App 也读取系统代理。
public enum NetworkMode: String, CaseIterable {
    case system
    case direct

    public static var current: NetworkMode {
        NetworkMode(rawValue: UserDefaults.standard.string(forKey: "networkMode") ?? "") ?? .system
    }

    public var label: String {
        switch self {
        case .system: return "跟随系统代理"
        case .direct: return "直接连接"
        }
    }

    public func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        if self == .direct { config.connectionProxyDictionary = [:] }
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return config
    }

    func curlArguments(for url: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                       proxies: [[String: Any]]? = nil) throws -> [String] {
        if self == .direct { return ["--proxy", "", "--noproxy", "*"] }
        // 终端用户显式设置的代理和 NO_PROXY 交由 curl 处理。
        let keys = url.scheme?.lowercased() == "https"
            ? ["https_proxy", "HTTPS_PROXY", "all_proxy", "ALL_PROXY"]
            : ["http_proxy", "all_proxy", "ALL_PROXY"]
        if keys.contains(where: { environment[$0]?.isEmpty == false }) { return [] }

        let resolved: [[String: Any]]
        if let proxies { resolved = proxies }
        else if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() {
            resolved = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue() as? [[String: Any]] ?? []
        } else { resolved = [] }
        guard let proxy = resolved.first,
              let type = proxy[kCFProxyTypeKey as String] as? String else { return ["--proxy", ""] }
        if type == kCFProxyTypeNone as String { return ["--proxy", ""] }
        if [kCFProxyTypeHTTP as String, kCFProxyTypeHTTPS as String, kCFProxyTypeSOCKS as String].contains(type) {
            guard let host = proxy[kCFProxyHostNameKey as String] as? String,
                  let port = proxy[kCFProxyPortNumberKey as String] as? Int else {
                throw URLError(.cannotFindHost)
            }
            let scheme = type == kCFProxyTypeSOCKS as String ? "socks5h" : "http"
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = port
            components.user = proxy[kCFProxyUsernameKey as String] as? String
            components.password = proxy[kCFProxyPasswordKey as String] as? String
            guard let address = components.string else { throw URLError(.badURL) }
            return ["--proxy", address]
        } else {
            throw NSError(domain: "PureListen.Network", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "API 暂不支持 PAC 自动代理，请在系统设置中配置 HTTP(S) 或 SOCKS 代理。"
            ])
        }
    }
}
