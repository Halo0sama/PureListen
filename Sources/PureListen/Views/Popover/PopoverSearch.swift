import SwiftUI
import PureListenCore

// MARK: - 统一搜索页(歌曲搜索 + 链接直达)

/// 把原来散落的三种入口合并到一处:
/// 1. 搜索网易云曲库（输入歌名/歌手）；
/// 2. 粘贴网易云歌曲链接 / 歌曲 ID；
/// 3. 粘贴 B站链接 / BV号 / 音频直链 —— 直接解析播放。
struct PopoverSearchPage: View {
    @EnvironmentObject var state: AppState

    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.Space.m) {
            DSSearchField(placeholder: "搜索歌曲 / 歌手，或粘贴链接",
                          text: $input,
                          isBusy: state.searchBusy || state.quickPlayBusy) {
                submit()
            }
            .focused($focused)
            .padding(.horizontal, DS.Space.l)

            if let kind = resolutionLabel {
                directResolveCard(kind: kind)
                    .padding(.horizontal, DS.Space.l)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, DS.Space.xs)
        .animation(DS.Motion.standard, value: resolutionLabel)
        .onAppear {
            if input.isEmpty { input = state.searchKeyword }
            // 进入搜索页就把焦点给输入框（稍等一拍, 避免和 popover 首次布局抢焦点）。
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                focused = true
            }
        }
    }

    // MARK: 链接直达

    /// 输入被识别成链接/ID 时, 告诉用户"回车就直接播放"。
    private var resolutionLabel: String? {
        guard let (kind, _) = SourceResolver.classify(input) else { return nil }
        switch kind {
        case "netease": return "网易云歌曲"
        case "bilibili": return "哔哩哔哩视频"
        case "direct": return "音频直链"
        default: return nil
        }
    }

    private func directResolveCard(kind: String) -> some View {
        Button {
            submit()
        } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: directIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("识别为\(kind)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("按回车直接解析并播放")
                        .font(DS.TypeScale.meta)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer(minLength: 0)
                if state.quickPlayBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var directIcon: String {
        guard let (kind, _) = SourceResolver.classify(input) else { return "link" }
        switch kind {
        case "netease": return "music.note"
        case "bilibili": return "play.rectangle"
        default: return "link"
        }
    }

    // MARK: 结果

    @ViewBuilder
    private var results: some View {
        if state.searchResults.isEmpty && !state.searchBusy {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                if state.searchBusy && state.searchResults.isEmpty {
                    ProgressView().controlSize(.small).padding(.top, 50)
                } else {
                    HStack {
                        Text("歌曲")
                            .font(DS.TypeScale.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.Palette.textSecondary)
                        Text("\(state.searchResults.count)")
                            .font(DS.TypeScale.meta)
                            .foregroundStyle(DS.Palette.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.l)
                    .padding(.bottom, 4)

                    ForEach(state.searchResults) { track in
                        SearchTrackRow(track: track)
                            .padding(.horizontal, DS.Space.s)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .contentMargins(.bottom, 132, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
            .dsScrollFade(top: 24)
        .padding(.horizontal, DS.Space.popoverPadding - DS.Space.s)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)
            DSEmptyState(systemImage: "magnifyingglass",
                         title: "搜索与直达",
                         message: "输入歌名或歌手搜索网易云曲库")
            VStack(spacing: DS.Space.s) {
                hintRow(icon: "link", tint: .orange, title: "粘贴链接直达",
                        detail: "网易云 / B站 链接、BV号、音频直链")
                hintRow(icon: "clock.arrow.circlepath", tint: .mint, title: "回车即搜",
                        detail: "搜索结果显示后, 点一下即可播放")
            }
            .padding(.horizontal, DS.Space.xl)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s)
    }

    private func hintRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: DS.Space.m) {
            DSGlyphTile(systemName: icon, tint: tint, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(detail)
                    .font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 提交

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        // 链接 / ID / 直链: 走解析播放（原来"快捷播放"的能力）。
        if SourceResolver.classify(value) != nil {
            state.resolveAndPlay(value)
            focused = false
            return
        }

        // 普通文本: 搜索网易云曲库。
        state.searchKeyword = value
        state.doSearch()
        focused = false
    }
}

// MARK: - 搜索结果行

private struct SearchTrackRow: View {
    @EnvironmentObject var state: AppState
    let track: NCTrack

    var body: some View {
        DSListRow(title: track.name, subtitle: track.artists, height: 46) {
            let index = state.appendTrack(track)
            state.play(index: index)
        } leading: {
            CoverArtwork(url: track.coverURL, size: 34, radius: DS.Radius.artSmall,
                         shadow: true, borderOpacity: 0.12)
        } trailing: {
            if track.vipOnly {
                DSChip(text: "VIP", tone: .neutral, compact: true)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Palette.textQuaternary)
            }
        }
    }
}
