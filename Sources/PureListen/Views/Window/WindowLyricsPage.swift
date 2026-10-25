import SwiftUI

// MARK: - 「歌词」页

/// 逐行居中的歌词: 当前行放大加粗, 点击任意一行跳转, 自动滚动到中央。
struct WindowLyricsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.albumTint) private var tint
    @Environment(\.dsIsDark) private var isDark

    private var hasLyrics: Bool { !state.lyrics.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            WindowPageToolbar(title: "歌词",
                              detail: hasLyrics ? "逐行 · 点击跳转" : nil)
            if hasLyrics {
                lyricsScroll
            } else {
                emptyState
            }
        }
    }

    // MARK: 滚动

    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: DS.Space.xl + DS.Space.xxs) {
                    ForEach(state.lyrics) { line in
                        WindowLyricRow(line: line,
                                       isCurrent: line.id == state.lyricIndex,
                                       isDark: isDark) {
                            state.seek(to: line.time)
                        }
                        .id(line.id)
                    }
                }
                .padding(.horizontal, DS.Space.windowPadding + DS.Space.xxl)
                .padding(.vertical, 230)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .mask(edgeFade)
            .onAppear { center(on: proxy, animated: false) }
            .onChange(of: state.lyricIndex) { _, _ in center(on: proxy, animated: true) }
            .onChange(of: state.currentIndex) { _, _ in
                // 切歌: 新歌词到达前先回到开头。
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    if let first = state.lyrics.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    /// 上下边缘的渐隐: 让首尾行从背景里浮出来, 而不是被硬切。
    private var edgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.00),
            .init(color: .white.opacity(0.35), location: 0.06),
            .init(color: .white, location: 0.22),
            .init(color: .white, location: 0.76),
            .init(color: .white.opacity(0.35), location: 0.94),
            .init(color: .clear, location: 1.00),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func center(on proxy: ScrollViewProxy, animated: Bool) {
        guard state.lyrics.indices.contains(state.lyricIndex) else { return }
        let id = state.lyrics[state.lyricIndex].id
        if animated {
            withAnimation(DS.Motion.page) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            DispatchQueue.main.async {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            DSEmptyState(systemImage: "quote.bubble",
                         title: "这首歌还没有歌词",
                         message: "仍然可以安静地听完 —— 无损音频正在直达耳机")
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 歌词行

private struct WindowLyricRow: View {
    var line: AppState.LyricLine
    var isCurrent: Bool
    var isDark: Bool
    var action: () -> Void

    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.xs) {
                Text(line.text)
                    .font(.system(size: isCurrent ? 22 : 15,
                                  weight: isCurrent ? .semibold : .medium))
                    .tracking(isCurrent ? DS.Tracking.display : 0)
                    .foregroundStyle(isCurrent
                                     ? DS.Palette.textPrimary
                                     : DS.Palette.textSecondary.opacity(isDark ? 0.66 : 0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(DS.Space.xs)

                if !line.translation.isEmpty {
                    Text(line.translation)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(isCurrent
                                         ? DS.Palette.textPrimary.opacity(0.72)
                                         : DS.Palette.textSecondary.opacity(isDark ? 0.40 : 0.48))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.m)
            .background {
                shape.fill(hovering && !isCurrent ? DS.Palette.surfaceHover.opacity(0.6) : .clear)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.quick) { hovering = value }
        }
        .animation(DS.Motion.standard, value: isCurrent)
        .accessibilityLabel(line.text)
    }
}
