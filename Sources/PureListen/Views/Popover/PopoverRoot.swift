import SwiftUI
import PureListenCore

// MARK: - 根视图

/// 菜单栏 popover 的根内容。
struct ContentView: View {
    @EnvironmentObject var state: AppState
    /// 预览/截图用: 直接落在某个页面。
    var initialRoute: PopoverRoute = .home
    var initialTab: PopoverTab = .playlists

    var body: some View {
        Group {
            if state.isLoggedIn {
                AlbumTintProvider(url: state.currentCoverURL) {
                    PopoverShell(initialRoute: initialRoute, initialTab: initialTab)
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
struct PopoverShell: View {
    @EnvironmentObject var state: AppState
    var initialRoute: PopoverRoute = .home
    var initialTab: PopoverTab = .playlists
    @StateObject private var router: PopoverRouter
    @State private var showNowPlayingWindow = false

    init(initialRoute: PopoverRoute = .home, initialTab: PopoverTab = .playlists) {
        self.initialRoute = initialRoute
        self.initialTab = initialTab
        _router = StateObject(wrappedValue: {
            let router = PopoverRouter()
            router.route = initialRoute
            router.tab = initialTab
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
            // 底部两角: 用画布色盖住 popover 圆角外侧的内容, 避免"列表被裁断"的错觉。
            LinearGradient(stops: [
                .init(color: DS.Palette.canvas.opacity(0), location: 0),
                .init(color: DS.Palette.canvas.opacity(0.86), location: 0.55),
                .init(color: DS.Palette.canvas, location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: 42)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // 底部渐隐: 让列表在玻璃台下方自然淡出, 而不是从圆角外侧被裁断。
                LinearGradient(colors: [DS.Palette.canvas.opacity(0), DS.Palette.canvas],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 38)
                    .allowsHitTesting(false)
                PopoverTransport()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .environmentObject(router)
        .frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
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
        HStack(spacing: DS.Space.s) {
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

            Spacer(minLength: DS.Space.s)

            if router.route == .settings {
                // 设置页没有其它动作: 右侧留空, 让页头只有一个返回。
                EmptyView()
            } else {
                HStack(spacing: 0) {
                    if router.route == .home {
                        DSIconButton(systemName: "macwindow.on.rectangle", size: 26, iconSize: 11,
                                     help: "打开播放窗口") {
                            state.onOpenNowPlaying?()
                        }
                    }
                    DSIconButton(systemName: "gearshape", size: 26, iconSize: 11, help: "设置") {
                        router.openSettings()
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
                .dsGlass(in: Capsule(style: .continuous), interactive: true,
                         fallbackFill: DS.Palette.surface)
            }
        }
        .padding(.horizontal, DS.Space.popoverPadding)
        .frame(height: 44)
    }

    private var title: String {
        switch router.route {
        case .home: return "净听"
        case .playlist: return state.currentPlaylist?.name ?? "歌单"
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
