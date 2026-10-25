import SwiftUI

// MARK: - 根视图

/// 「正在播放」窗口内容。
///
/// 结构: 氛围背景(模糊封面 + 遮罩 + 音乐色光晕) → 左侧 edge-to-edge 侧边栏 → 内容区 → 右上浮动音质胶囊。
/// 玻璃只出现在"浮在背景之上"的层(音质胶囊), 内容层全部是实体表面。
struct NowPlayingWindowView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var router: WindowRouter

    init(router: WindowRouter) {
        self.router = router
    }

    @MainActor
    init() {
        self.router = WindowRouter()
    }

    var body: some View {
        AlbumTintProvider(url: state.currentCoverURL, showsWash: false) {
            WindowShell(router: router)
        }
        .frame(minWidth: 820, minHeight: 560)
        .ignoresSafeArea()
        .background(Color.clear)
        .background(WindowActivationView().frame(width: 0, height: 0))
    }
}

// MARK: - 外壳

struct WindowShell: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var router: WindowRouter

    private var showsQualityCapsule: Bool {
        router.section != .settings && !state.trackStatus.title.isEmpty
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WindowAmbientBackground(url: state.currentCoverURL)

            HStack(spacing: 0) {
                WindowSidebar(router: router)
                    .frame(width: DS.Size.sidebarWidth)
                WindowContentArea(router: router)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showsQualityCapsule {
                WindowQualityCapsule()
                    .padding(.top, 13)
                    .padding(.trailing, DS.Space.xxl)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .background { WindowKeyboardShortcuts() }
        .animation(DS.Motion.standard, value: router.section)
        .animation(DS.Motion.quick, value: showsQualityCapsule)
    }
}

// MARK: - 键盘快捷键

/// 窗口级快捷键: 空格播放/暂停, ← → ±10 秒, ⌘← ⌘→ 上/下一首。
private struct WindowKeyboardShortcuts: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Button("") { state.playPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { seek(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { seek(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { state.playPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { state.playNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func seek(by delta: Double) {
        let total = max(state.trackStatus.seconds, 0)
        guard total > 0 else { return }
        let target = min(max(state.trackStatus.positionSeconds + delta, 0), total)
        state.seek(to: target)
    }
}

// MARK: - 内容区

struct WindowContentArea: View {
    @ObservedObject var router: WindowRouter

    var body: some View {
        ZStack {
            switch router.section {
            case .nowPlaying:
                WindowHeroPage()
                    .transition(.opacity)
            case .lyrics:
                WindowLyricsPage()
                    .transition(.opacity)
            case .signal:
                WindowSignalPage()
                    .transition(.opacity)
            case .settings:
                WindowSettingsPage()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
