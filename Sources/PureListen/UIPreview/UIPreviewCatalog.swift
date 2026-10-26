#if DEBUG
import AppKit
import SwiftUI
import PureListenCore

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
            name: "popover-home-idle",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.playerState = .idle
                state.trackStatus = ExclusivePlayer.TrackStatus()
                state.previewPlaybackQueue([], playlist: nil, index: -1)
                state.currentItem = nil
                state.lyrics = []
                state.volume = 0.25
            },
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
            name: "popover-bili",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.biliPhase = .idle
                state.biliUname = ""
            },
            makeView: { AnyView(ContentView(initialTab: .bilibili)) }
        ))

        scenes.append(.init(name: "refinement-neutral-tracks", presentation: .popover(size: popoverSize),
                            configure: { state in state.previewPlaybackQueue([], playlist: nil, index: -1) },
                            makeView: { AnyView(ContentView(initialRoute: .playlist)) }))
        scenes.append(.init(name: "refinement-bili-folders", presentation: .popover(size: popoverSize),
                            configure: { state in
                                state.biliPhase = .loggedIn
                                state.favFolders = state.favFolders.enumerated().map { index, folder in
                                    var folder = folder; folder.cover = "preview://cover/\(index)"; return folder
                                }
                            }, makeView: { AnyView(ContentView(initialTab: .bilibili)) }))
        scenes.append(.init(name: "refinement-bili-videos", presentation: .popover(size: popoverSize),
                            configure: { state in
                                state.biliPhase = .loggedIn
                                state.currentFavFolder = state.favFolders.first
                            }, makeView: { AnyView(ContentView(initialTab: .bilibili)) }))
        scenes.append(.init(name: "refinement-home-pressed", presentation: .popover(size: popoverSize),
                            configure: { _ in }, makeView: {
                                AnyView(ContentView().environment(\.glassLensDebugPoint, CGPoint(x: 70, y: 15)))
                            }))

        scenes.append(.init(name: "stream-buffering", presentation: .popover(size: popoverSize),
                            configure: { state in
                                state.trackStatus.buffering = true
                                state.trackStatus.downloadFraction = 0.55
                                state.trackStatus.downloadedBytes = state.trackStatus.sizeBytes / 2
                            }, makeView: { AnyView(ContentView(initialRoute: .nowPlaying)) }))

        scenes.append(.init(name: "controls-volume-expanded", presentation: .popover(size: popoverSize),
                            configure: { state in state.volume = 0.1 },
                            makeView: { AnyView(ContentView(initialVolumeExpanded: true)) }))
        scenes.append(.init(name: "controls-browsing-other-playlist", presentation: .popover(size: popoverSize),
                            configure: { state in
                                state.currentPlaylist = state.playlists[2]
                                state.tracks = Array(state.tracks.reversed())
                            }, makeView: { AnyView(ContentView(initialRoute: .playlist)) }))
        scenes.append(.init(name: "controls-shuffle", presentation: .popover(size: popoverSize),
                            configure: { state in state.playbackMode = .shuffle },
                            makeView: { AnyView(ContentView(initialRoute: .nowPlaying)) }))
        scenes.append(.init(name: "controls-repeat-one", presentation: .popover(size: popoverSize),
                            configure: { state in state.playbackMode = .repeatOne },
                            makeView: { AnyView(ContentView()) }))

        scenes.append(.init(name: "controls-list-scrolled", presentation: .popover(size: popoverSize),
                            settleTime: 1.4, configure: { _ in },
                            makeView: { AnyView(ControlsScrolledPreview()) }))

        // MARK: 统一搜索页(空状态 / 已有关键词与结果 / 链接直达)

        scenes.append(.init(
            name: "popover-search",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.searchKeyword = ""
                state.searchResults = []
            },
            makeView: { AnyView(ContentView(initialRoute: .search)) }
        ))

        scenes.append(.init(
            name: "popover-search-results",
            presentation: .popover(size: popoverSize),
            settleTime: 1.2,
            configure: { state in
                state.searchKeyword = "坂本龍一"
                state.searchResults = Array(state.tracks.prefix(9))
            },
            makeView: { AnyView(ContentView(initialRoute: .search)) }
        ))

        // MARK: Popover 内的「正在播放」(播放 / 歌词)

        scenes.append(.init(
            name: "popover-nowplaying",
            presentation: .popover(size: popoverSize),
            settleTime: 1.3,
            configure: { state in
                state.volume = 1.0
                state.playerState = .playing
            },
            makeView: { AnyView(ContentView(initialRoute: .nowPlaying)) }
        ))

        scenes.append(.init(
            name: "popover-nowplaying-lyrics",
            presentation: .popover(size: popoverSize),
            settleTime: 1.4,
            configure: { state in
                state.volume = 1.0
                state.playerState = .playing
            },
            makeView: {
                AnyView(ContentView(initialRoute: .nowPlaying,
                                    initialNowPlayingPane: .lyrics))
            }
        ))

        // 小播放器中的共享链路：原生、重采样、暂停与无曲目。
        for variant in ["native", "resampled", "paused", "idle"] {
            scenes.append(.init(
                name: "popover-signal-\(variant)",
                presentation: .popover(size: popoverSize),
                settleTime: 1.0,
                configure: { state in
                    state.volume = 0.1
                    if variant == "resampled" {
                        state.trackStatus.fileRate = 192000
                        state.trackStatus.fileBits = 24
                        state.trackStatus.deviceRate = 96000
                        state.trackStatus.resampled = true
                        state.trackStatus.level = "hires"
                    } else if variant == "paused" {
                        state.playerState = .paused
                        state.trackStatus.exclusive = false
                    } else if variant == "idle" {
                        state.playerState = .idle
                        state.trackStatus = ExclusivePlayer.TrackStatus()
                        state.previewPlaybackQueue([], playlist: nil, index: -1)
                    }
                },
                makeView: {
                    AnyView(ContentView(initialRoute: .nowPlaying,
                                        initialNowPlayingPane: .signal))
                }
            ))
        }

        scenes.append(.init(
            name: "popover-settings",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { _ in },
            makeView: { AnyView(ContentView(initialRoute: .settings)) }
        ))

        scenes.append(.init(
            name: "popover-reconnect-error",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.playerState = .error("输出设备未就绪，请连接后点击播放")
                state.trackStatus.exclusive = false
                state.volume = 0.1
            },
            makeView: { AnyView(ContentView(initialRoute: .nowPlaying)) }
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

        // MARK: 封面 URL 切换回归检查（不能显示上一个 URL 的图）
        scenes.append(.init(
            name: "cover-swap-check",
            presentation: .popover(size: popoverSize),
            settleTime: 1.2,
            configure: { _ in },
            makeView: { AnyView(CoverSwapPreview()) }
        ))

        // MARK: 液态玻璃交互（按下时的指针透镜/内部照明）预览
        scenes.append(.init(
            name: "glass-lens",
            presentation: .popover(size: popoverSize),
            settleTime: 0.9,
            configure: { _ in },
            makeView: { AnyView(GlassLensPreview()) }
        ))

        return scenes
    }
}

/// 封面 URL 切换检查: 0.4 秒后把 URL 换成另一张封面，截图应显示第二张。
private struct CoverSwapPreview: View {
    @State private var url = "preview://cover/1"

    var body: some View {
        VStack(spacing: DS.Space.l) {
            CoverArtwork(url: url, size: 140, radius: 26, shadow: true)
            Text(url)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
            Text("0.4 秒后切换 URL，这里应显示第二张封面")
                .font(.system(size: 10.5))
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(30)
        .frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
        .task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            url = "preview://cover/2"
        }
    }
}

/// 交互预览: 通过环境变量把指针"固定"在控件里, 截图能看到按下时的透镜光斑。
/// 真实运行时这层效果由鼠标事件驱动。
private struct GlassLensPreview: View {
    @State private var tab = 0
    @State private var pane = 0
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [DS.Palette.canvas, DS.Palette.canvasElevated],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("按住并拖动玻璃控件：整枚透镜胶囊放大并跟随指针")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)

                DSSegmented(items: [0, 1],
                            title: { ["网易云", "哔哩哔哩"][$0] },
                            selection: $tab, height: 30)
                    .environment(\.glassLensDebugPoint, CGPoint(x: 86, y: 15))

                HStack(spacing: 9) {
                    DSGlassIconButton(systemName: "magnifyingglass", help: "搜索") {}
                        .environment(\.glassLensDebugPoint, CGPoint(x: 20, y: 19))
                    DSGlassIconButton(systemName: "macwindow.on.rectangle", help: "打开播放窗口") {}
                        .environment(\.glassLensDebugPoint, CGPoint(x: 58, y: 19))
                    Spacer(minLength: 0)
                }

                DSSegmented(items: [0, 1],
                            title: { ["播放", "歌词"][$0] },
                            selection: $pane, height: 26)
                    .environment(\.glassLensDebugPoint, CGPoint(x: 128, y: 13))

                Text("分段控件：按下时整枚选中胶囊整体放大成透镜，跟随指针移动，松手落到目标分段。")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(DS.Palette.textTertiary)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight, alignment: .top)
    }
}

private struct ControlsScrolledPreview: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollViewReader { proxy in
            ContentView().task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if state.playlists.count > 3 { proxy.scrollTo(state.playlists[3].id, anchor: .top) }
            }
        }
    }
}
#endif
