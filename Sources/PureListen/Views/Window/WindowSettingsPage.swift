import SwiftUI

// MARK: - 「设置」页

/// 窗口内的设置页: 页头由窗口提供, 内容交给 `SettingsView(layout: .window)`。
///
/// `SettingsView` 自带内部滚动与 28pt 左右留白(与窗口页头对齐), 因此这里不再
/// 包一层 ScrollView、也不追加水平内边距, 避免双重滚动与双重留白。
///
/// 设置卡片是半透明表面, 所以先把内容区压回中性底(顶部渐隐衔接氛围背景),
/// 卡片才不会透出封面的洗色; 同时统一 tint, 让开关/选择器等原生控件的强调色
/// 跟随当前封面的音乐色, 而不是系统蓝。
struct WindowSettingsPage: View {
    @Environment(\.albumTint) private var tint
    @Environment(\.dsIsDark) private var isDark

    var body: some View {
        VStack(spacing: 0) {
            WindowPageToolbar(title: "设置", detail: "净听 · 偏好")
            SettingsView(layout: .window)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(tint)
        }
        .background {
            linearScrim
                .ignoresSafeArea()
        }
    }

    /// 顶部轻、向下逐渐回到中性 canvas 的压暗层。
    private var linearScrim: some View {
        LinearGradient(stops: [
            .init(color: DS.Palette.canvas.opacity(0.0), location: 0.00),
            .init(color: DS.Palette.canvas.opacity(isDark ? 0.55 : 0.44), location: 0.14),
            .init(color: DS.Palette.canvas.opacity(isDark ? 0.72 : 0.60), location: 0.45),
            .init(color: DS.Palette.canvas.opacity(isDark ? 0.72 : 0.60), location: 1.00),
        ], startPoint: .top, endPoint: .bottom)
    }
}
