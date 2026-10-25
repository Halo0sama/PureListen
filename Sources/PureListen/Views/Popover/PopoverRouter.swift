import SwiftUI
import PureListenCore

// MARK: - Popover 路由

enum PopoverTab: Hashable, CaseIterable {
    case playlists
    case search
    case bilibili

    var title: String {
        switch self {
        case .playlists: return "歌单"
        case .search: return "搜索"
        case .bilibili: return "B站"
        }
    }

    var icon: String {
        switch self {
        case .playlists: return "square.stack"
        case .search: return "magnifyingglass"
        case .bilibili: return "play.rectangle"
        }
    }
}

enum PopoverRoute: Equatable {
    case home
    case playlist
    case settings
}

@MainActor
final class PopoverRouter: ObservableObject {
    @Published var route: PopoverRoute = .home
    @Published var tab: PopoverTab = .playlists

    func openPlaylist() {
        withAnimation(DS.Motion.page) { route = .playlist }
    }

    func openSettings() {
        withAnimation(DS.Motion.page) { route = .settings }
    }

    func home() {
        withAnimation(DS.Motion.page) { route = .home }
    }

    func back() {
        withAnimation(DS.Motion.page) { route = .home }
    }
}
