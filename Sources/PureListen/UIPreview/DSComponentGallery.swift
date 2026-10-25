#if DEBUG
import SwiftUI

/// 设计系统总览: 用来在真实系统渲染下检查玻璃、圆角、字阶与色彩关系。
struct DSComponentGallery: View {
    @State private var segment = 0
    @State private var progress: Double = 0.34
    @State private var volume: Double = 0.72
    @State private var toggleValue = true
    @State private var searchText = "坂本龍一"

    private let cover = "preview://cover/5"
    @Environment(\.albumTint) private var tint

    var body: some View {
        AlbumTintProvider(url: cover) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    header
                    heroCard
                    segmented
                    listSection
                    seekSection
                    controls
                    chipsSection
                    settingsSection
                    typeSpecimen
                }
                .padding(DS.Space.popoverPadding)
            }
        }
        .frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
    }

    private var header: some View {
        HStack(spacing: DS.Space.m) {
            DSBrandMark(size: 18)
            Text("净听")
                .font(.system(size: 13, weight: .semibold))
                .tracking(DS.Tracking.tight)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer()
            DSIconButton(systemName: "gearshape", help: "设置") {}
        }
    }

    private var heroCard: some View {
        HStack(spacing: DS.Space.l) {
            CoverArtwork(url: cover, size: 72, radius: DS.Radius.art, shadow: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("夏夜の幻灯")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("坂本龍一 / 青葉市子")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                HStack(spacing: 4) {
                    DSChip(text: "无损", tone: .accent)
                    DSChip(text: "44.1kHz · 16bit")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.l)
        .dsSurface(DS.Radius.card)
    }

    private var segmented: some View {
        DSSegmented(items: [0, 1, 2], title: { ["我的歌单", "搜索", "B站收藏"][$0] },
                    selection: $segment)
    }

    private var listSection: some View {
        VStack(spacing: 2) {
            DSSectionHeader(title: "歌单", detail: "12")
                .padding(.bottom, 2)
            ForEach(0..<3, id: \.self) { index in
                DSListRow(title: ["深夜书房", "昭和歌谣", "雨的声音"][index],
                          subtitle: "\([42, 18, 76][index]) 首",
                          isSelected: index == 0) {
                    // action
                } leading: {
                    CoverArtwork(url: "preview://cover/\(index)", size: 30,
                                 radius: DS.Radius.artSmall)
                } trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Palette.textQuaternary)
                }
            }
        }
    }

    private var seekSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSeekBar(progress: progress, tint: tint,
                      onScrub: { progress = $0 },
                      onScrubbing: { progress = $0 })
            HStack {
                Text("01:27").font(DS.TypeScale.timecode)
                Spacer()
                Text("-02:47").font(DS.TypeScale.timecode)
            }
            .foregroundStyle(DS.Palette.textTertiary)
            DSVolumeBar(volume: volume, tint: tint, onVolume: { volume = $0 })
        }
    }

    private var controls: some View {
        HStack(spacing: DS.Space.xl) {
            DSIconButton(systemName: "backward.fill", size: 30, iconSize: 12) {}
            DSPlayButton(isPlaying: true, size: 40) {}
            DSIconButton(systemName: "forward.fill", size: 30, iconSize: 12) {}
            Spacer()
            DSWaveform(isPlaying: true, tint: tint)
            DSChip(text: "位完美", systemImage: "checkmark.seal.fill", tone: .mint)
        }
    }

    private var chipsSection: some View {
        HStack(spacing: 5) {
            DSChip(text: "44.1kHz/16bit")
            DSChip(text: "独占输出", tone: .accent)
            DSChip(text: "FLAC")
            DSChip(text: "Hi-Res", tone: .amber)
            DSChip(text: "VIP", tone: .rose, compact: true)
            Spacer()
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            DSSettingRow(title: "接管媒体键", subtitle: "播放/暂停与上下曲由本 App 响应") {
                Toggle("", isOn: $toggleValue)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            DSSoftDivider().padding(.leading, 44)
            DSSettingRow(title: "音质", subtitle: "内置耳机孔最高 96kHz") {
                Text("无损 FLAC")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .dsSurface(DS.Radius.card)
    }

    private var typeSpecimen: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("HERO TITLE").dsMicroLabel()
            Text("夏夜の幻灯")
                .font(DS.TypeScale.heroTitle)
                .tracking(DS.Tracking.display)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("Subtitle / 副标题")
                .font(DS.TypeScale.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("正文 Body 12.5 —— 声音绕过系统混音器, 直接写入耳机孔。")
                .font(DS.TypeScale.body)
                .foregroundStyle(DS.Palette.textSecondary)
            HStack(spacing: DS.Space.m) {
                DSChip(text: "位完美", tone: .mint)
                Text("44.1kHz / 16bit").font(DS.TypeScale.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            DSSearchField(placeholder: "搜索歌曲 / 歌手", text: $searchText) {}
        }
    }
}
#endif
