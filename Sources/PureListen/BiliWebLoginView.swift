import SwiftUI
import WebKit
import PureListenCore

/// B 站网页登录(WebView 兜底, NeriPlayer 同款思路):
/// 真浏览器引擎加载登录页(QR/账密均可), SESSDATA 出现在 Cookie 存储即登录成功。
struct BiliWebLoginView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("哔哩哔哩 · 网页登录").font(.headline)
                Spacer()
                Button("完成") { NSApp.keyWindow?.close() }.buttonStyle(.link)
            }
            .padding(10)
            Text("扫码或账密登录, 检测到登录态后自动完成")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Divider()
            BiliWebView(onCookies: { cookies in
                state.finishBiliWebLogin(webCookies: cookies)
            })
        }
        .frame(minWidth: 520, minHeight: 660)
    }
}

struct BiliWebView: NSViewRepresentable {
    var onCookies: ([String: String]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()   // 干净会话
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCookies: onCookies) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookies: ([String: String]) -> Void
        weak var webView: WKWebView?
        private var pollTimer: Timer?

        init(onCookies: @escaping ([String: String]) -> Void) {
            self.onCookies = onCookies
            super.init()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
            RunLoop.main.add(pollTimer!, forMode: .common)
        }

        deinit { pollTimer?.invalidate() }

        func checkCookies() {
            guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
            store.getAllCookies { [weak self] cookies in
                var dict: [String: String] = [:]
                for cookie in cookies where cookie.domain.contains("bilibili.com") {
                    dict[cookie.name] = cookie.value
                }
                if dict["SESSDATA"]?.isEmpty == false {
                    self?.pollTimer?.invalidate()
                    self?.onCookies(dict)
                }
            }
        }
    }
}
