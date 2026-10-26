import SwiftUI

/// 有曲目时仍显示恢复失败/准备进度，避免播放键看起来没有反应。
struct PlaybackControlStatus: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if case let .error(message) = state.playerState {
            Text(message)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.Palette.amber)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .help(message)
                .padding(.top, 8)
        } else if state.trackStatus.buffering {
            Text("缓冲中…")
                .font(DS.TypeScale.caption).foregroundStyle(DS.Palette.textSecondary).padding(.top, 8)
        } else if case let .loading(message) = state.playerState {
            Text(message)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .padding(.top, 8)
        }
    }
}
