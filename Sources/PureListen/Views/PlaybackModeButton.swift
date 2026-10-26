import SwiftUI

struct PlaybackModeButton: View {
    @EnvironmentObject var state: AppState
    var size: CGFloat = 26

    var body: some View {
        DSIconButton(systemName: state.playbackMode.symbol, size: size, iconSize: 12,
                     isActive: state.playbackMode != .sequential, help: state.playbackMode.title) {
            state.playbackMode = state.playbackMode.next
        }
        .accessibilityValue(state.playbackMode.title)
        .contextMenu {
            ForEach(PlaybackMode.allCases, id: \.self) { mode in
                Button { state.playbackMode = mode } label: {
                    Label(mode.title, systemImage: state.playbackMode == mode ? "checkmark" : mode.symbol)
                }
            }
        }
    }
}
