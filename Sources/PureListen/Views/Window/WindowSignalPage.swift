import SwiftUI

/// 窗口模式的链路页，与小播放器复用同一份内容。
struct WindowSignalPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            WindowPageToolbar(title: "播放链路",
                              detail: state.trackStatus.title.isEmpty ? nil : "音源 → 解码 → 缓冲 → 独占 → 设备")
            PlaybackSignalView()
        }
    }
}
