import AppKit

@main
enum PureListenApp {
    @MainActor
    static func main() {
        #if DEBUG
        // 无音频 UI 截图模式(仅 Debug 存在): 渲染界面并抓图后退出。
        if UIPreviewStudio.isRequested {
            UIPreviewStudio.run()
            return
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
