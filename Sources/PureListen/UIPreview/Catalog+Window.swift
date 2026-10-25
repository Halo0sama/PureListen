#if DEBUG
import AppKit
import SwiftUI
import PureListenCore

/// 主窗口截图场景(由 Window 负责同学维护)。
@MainActor
enum WindowPreviewScenes {

    private static var defaultSize: CGSize {
        CGSize(width: DS.Size.windowWidth, height: DS.Size.windowHeight)
    }

    private static func scene(_ name: String,
                              section: NowPlayingSection = .nowPlaying,
                              size: CGSize? = nil,
                              settleTime: TimeInterval = 1.2,
                              configure: @escaping (AppState) -> Void = { _ in }) -> UIPreviewScene {
        UIPreviewScene(
            name: name,
            presentation: .window(PreviewWindowConfig(size: size ?? defaultSize, title: "净听")),
            settleTime: settleTime,
            withShadow: true,
            anchor: nil,
            configure: configure,
            makeView: {
                AnyView(NowPlayingWindowView(router: WindowRouter(section: section)))
            }
        )
    }

    static func scenes() -> [UIPreviewScene] {
        [
            // 门面: 大封面 + 完整播放控制。
            scene("window-hero") { state in
                state.volume = 1.0
                state.playerState = .playing
            },

            // 歌词: 当前行居中放大。
            scene("window-lyrics", section: .lyrics) { state in
                state.volume = 1.0
                state.playerState = .playing
            },

            // 播放链路: 端到端信号流。
            scene("window-signal", section: .signal) { state in
                state.volume = 1.0
                state.playerState = .playing
            },

            // 设置: 由 Settings 同学填充内容, 这里验证窗口容器与页头。
            scene("window-settings", section: .settings),

            // 空状态: 还没有开始播放。
            scene("window-idle") { state in
                state.playerState = .idle
                state.trackStatus = ExclusivePlayer.TrackStatus()
                state.currentIndex = -1
                state.currentItem = nil
                state.tracks = []
                state.currentPlaylist = nil
                state.lyrics = []
                state.lyricIndex = -1
            },

            // 最小窗口尺寸下的紧凑排版。
            scene("window-compact", size: CGSize(width: 820, height: 560)) { state in
                state.volume = 1.0
                state.playerState = .playing
            },
        ]
    }
}
#endif

