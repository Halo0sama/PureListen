import SwiftUI

struct PopoverVolumeOverlay: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: PopoverRouter
    @Environment(\.albumTint) private var tint
    @State private var unmutedVolume: Float = 0.1

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.10)
                .contentShape(Rectangle())
                .onTapGesture { router.volumeExpanded = false }
                .accessibilityLabel("关闭音量控制")

            VStack(spacing: 12) {
                Text("\(Int((state.volume * 100).rounded()))%")
                    .font(DS.TypeScale.timecode)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(height: 16)

                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(DS.Palette.surfaceSelected)
                        Capsule().fill(tint)
                            .frame(height: geometry.size.height * CGFloat(state.volume))
                    }
                    .frame(width: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                        let value = 1 - gesture.location.y / max(geometry.size.height, 1)
                        state.setManualVolume(Float(min(max(value, 0), 1)))
                    })
                }
                .accessibilityElement()
                .accessibilityLabel("音量")
                .accessibilityValue("\(Int((state.volume * 100).rounded()))%")
                .accessibilityAdjustableAction { direction in
                    let delta: Float = direction == .increment ? 0.05 : -0.05
                    state.setManualVolume(min(max(state.volume + delta, 0), 1))
                }

                Button {
                    state.setManualVolume(state.volume > 0 ? 0 : unmutedVolume)
                } label: {
                    Image(systemName: state.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .help(state.volume == 0 ? "取消静音" : "静音")
            }
            .padding(.vertical, 14)
            .frame(width: 44)
            .dsGlass(in: Capsule(), castsShadow: false)
            .clipShape(Capsule())
            .padding(.trailing, 9)
            .padding(.bottom, 12)
            .onAppear { if state.volume > 0 { unmutedVolume = state.volume } }
            .onChange(of: state.volume) { _, value in if value > 0 { unmutedVolume = value } }
        }
    }
}
