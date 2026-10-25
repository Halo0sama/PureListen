#if DEBUG
import AppKit
import SwiftUI

/// 截图场景清单: 新增/调整界面时, 在这里登记需要出图的画面。
@MainActor
enum UIPreviewCatalog {

    private static var popoverSize: CGSize {
        CGSize(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
    }

    static func scenes() -> [UIPreviewScene] {
        var scenes: [UIPreviewScene] = []

        scenes.append(.init(
            name: "gallery",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { _ in },
            makeView: { AnyView(DSComponentGallery()) }
        ))

        scenes.append(.init(
            name: "popover-home",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { _ in },
            makeView: { AnyView(ContentView()) }
        ))

        scenes.append(.init(
            name: "popover-tracks",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.currentPlaylist = state.playlists.first
            },
            makeView: { AnyView(ContentView(initialRoute: .playlist)) }
        ))

        scenes.append(.init(
            name: "popover-search",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { _ in },
            makeView: { AnyView(ContentView(initialTab: .search)) }
        ))

        scenes.append(.init(
            name: "popover-bili",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { _ in },
            makeView: { AnyView(ContentView(initialTab: .bilibili)) }
        ))

        scenes.append(.init(
            name: "popover-settings",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { _ in },
            makeView: { AnyView(ContentView(initialRoute: .settings)) }
        ))

        scenes.append(.init(
            name: "popover-login",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.profile = nil
                state.loginPhase = .qrWaiting
                state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
            },
            makeView: { AnyView(ContentView()) }
        ))

        scenes.append(.init(
            name: "popover-login-scanned",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.profile = nil
                state.loginPhase = .qrScanned
                state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
            },
            makeView: { AnyView(ContentView()) }
        ))

        scenes.append(contentsOf: WindowPreviewScenes.scenes())
        scenes.append(contentsOf: SettingsPreviewScenes.scenes())

        return scenes
    }
}
#endif
