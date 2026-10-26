import SwiftUI
import PureListenCore

// MARK: - Popover 路由

enum PopoverTab: Hashable, CaseIterable {
    case playlists
    case bilibili

    var title: String {
        switch self {
        case .playlists: return "歌单"
        case .bilibili: return "B站"
        }
    }
}

enum PopoverRoute: Equatable {
    case home
    case playlist
    case search
    case nowPlaying
    case settings
}

@MainActor
final class PopoverRouter: ObservableObject {
    @Published var route: PopoverRoute = .home
    @Published var tab: PopoverTab = .playlists
    @Published var nowPlayingPane: NowPlayingPane = .player

    /// 简单历史栈: 让"返回"回到进入前的那一页（例如从歌单打开正在播放）。
    private var history: [PopoverRoute] = []

    func push(_ route: PopoverRoute) {
        guard route != self.route else { return }
        history.append(self.route)
        withAnimation(DS.Motion.page) { self.route = route }
    }

    func openPlaylist() { push(.playlist) }
    func openSearch() { push(.search) }
    func openNowPlaying(pane: NowPlayingPane = .player) {
        nowPlayingPane = pane
        push(.nowPlaying)
    }
    func openSettings() { push(.settings) }

    func back() {
        let target = history.popLast() ?? .home
        withAnimation(DS.Motion.page) { route = target }
    }

    func home() {
        history.removeAll()
        withAnimation(DS.Motion.page) { route = .home }
    }
}
