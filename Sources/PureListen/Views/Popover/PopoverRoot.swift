import SwiftUI
import PureListenCore

// MARK: - 根视图

/// 菜单栏 popover 的根内容。
struct ContentView: View {
    @EnvironmentObject var state: AppState
    /// 预览/截图用: 直接落在某个页面。
    var initialRoute: PopoverRoute = .home
    var initialTab: PopoverTab = .playlists
    var initialNowPlayingPane: NowPlayingPane = .player

    var body: some View {
        Group {
            if state.isLoggedIn {
                AlbumTintProvider(url: state.currentCoverURL) {
                    PopoverShell(initialRoute: initialRoute, initialTab: initialTab,
                                 initialNowPlayingPane: initialNowPlayingPane)
                }
            } else {
                LoginView()
            }
        }
        .frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
        .background(Color.clear)
    }
}

// MARK: - 外壳

/// 顶栏 + 内容 + 浮动播放台。
///
/// 「正在播放」页自己就是完整播放器, 所以那一页隐藏底部玻璃台, 避免两套控制重复。
struct PopoverShell: View {
    @EnvironmentObject var state: AppState
    var initialRoute: PopoverRoute = .home
    var initialTab: PopoverTab = .playlists
    var initialNowPlayingPane: NowPlayingPane = .player
    @StateObject private var router: PopoverRouter

    init(initialRoute: PopoverRoute = .home, initialTab: PopoverTab = .playlists,
         initialNowPlayingPane: NowPlayingPane = .player) {
        self.initialRoute = initialRoute
        self.initialTab = initialTab
        self.initialNowPlayingPane = initialNowPlayingPane
        _router = StateObject(wrappedValue: {
            let router = PopoverRouter()
            router.route = initialRoute
            router.tab = initialTab
            router.nowPlayingPane = initialNowPlayingPane
            return router
        }())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PopoverTopBar(router: router)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .mask {
                if router.route == .nowPlaying {
                    Color.white
                } else {
                    // 隐去列表本身及其封面投影，避免透过玻璃形成局部色块。
                    VStack(spacing: 0) {
                        Color.white
                        LinearGradient(colors: [.white, .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 38)
                        Color.clear.frame(height: 112)
                    }
                }
            }

            if router.route != .nowPlaying {
                PopoverTransport()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(router)
        .frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
        .animation(DS.Motion.page, value: router.route)
        .onAppear {
            // 打开面板时不要让输入框抢到焦点: 用户第一下应该是"看"而不是"输"。
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.route {
        case .home:
            PopoverHome()
                .transition(.opacity)
        case .playlist:
            PopoverTrackList()
                .transition(.opacity)
        case .search:
            PopoverSearchPage()
                .transition(.opacity)
        case .nowPlaying:
            PopoverNowPlayingPage()
                .transition(.opacity)
        case .settings:
            PopoverSettingsPage()
                .transition(.opacity)
        }
    }
}

// MARK: - 顶栏

struct PopoverTopBar: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var router: PopoverRouter

    var body: some View {
        HStack(spacing: 6) {
            if router.route != .home {
                DSIconButton(systemName: "chevron.left", size: 26, iconSize: 11,
                             help: "返回") { router.back() }
                    .padding(.leading, -6)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(DS.TypeScale.navTitle)
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.TypeScale.meta)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, router.route == .home ? 2 : 0)

            Spacer(minLength: 4)

            // 搜索: 单独拎出来的一枚玻璃圆钮, 就在「窗口模式」左边。
            if router.route != .search {
                DSGlassIconButton(systemName: "magnifyingglass", help: "搜索") {
                    router.openSearch()
                }
            }

            // 窗口模式: 保留原来的「打开独立播放窗口」功能。
            DSGlassPillButton(title: "窗口模式", systemImage: "macwindow.on.rectangle") {
                state.onOpenNowPlaying?()
            }

            if router.route != .settings {
                DSGlassIconButton(systemName: "gearshape", help: "设置") {
                    router.openSettings()
                }
            }
        }
        .padding(.horizontal, DS.Space.popoverPadding)
        .frame(height: 44)
    }

    private var title: String {
        switch router.route {
        case .home: return "净听"
        case .playlist: return state.currentPlaylist?.name ?? "歌单"
        case .search: return "搜索"
        case .nowPlaying: return "正在播放"
        case .settings: return "设置"
        }
    }

    private var subtitle: String? {
        switch router.route {
        case .home:
            let name = state.profile?.nickname ?? ""
            return name.isEmpty ? "纯净聆听" : "网易云 · \(name)"
        case .playlist:
            guard let playlist = state.currentPlaylist else { return nil }
            return "\(playlist.trackCount) 首 · 网易云歌单"
        case .search:
            return "搜索歌曲 · 粘贴链接直达"
        case .nowPlaying:
            let artist = state.trackStatus.artist
            return artist.isEmpty ? state.currentSourceLabel : artist
        case .settings:
            return "外观与播放偏好"
        }
    }
}

// MARK: - 设置页容器

struct PopoverSettingsPage: View {
    var body: some View {
        SettingsView(layout: .popover)
            // 给浮动播放台留出空间, 否则最后一张卡片会被玻璃台切在中间。
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 112)
            }
    }
}
