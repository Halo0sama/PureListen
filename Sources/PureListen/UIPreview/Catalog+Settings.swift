#if DEBUG
import AppKit
import SwiftUI
import PureListenCore

// MARK: - 设置页 / 登录页 / B站网页登录 截图场景
//
// 场景名以 settings / login / bili 开头, 方便 --only 过滤而不覆盖其他人的截图。

@MainActor
enum SettingsPreviewScenes {

    private static var popoverSize: CGSize {
        CGSize(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)
    }

    static func scenes() -> [UIPreviewScene] {
        var scenes: [UIPreviewScene] = []

        // MARK: 真实 popover 外壳里的设置页 (最终交付形态)

        scenes.append(.init(
            name: "settings-popover",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { state in
                state.mediaControlKeysEnabled = false
            },
            makeView: { AnyView(ContentView(initialRoute: .settings)) }
        ))

        // MARK: 哔哩哔哩未登录 / 扫码中

        scenes.append(.init(
            name: "settings-popover-bili",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.mediaControlKeysEnabled = false
                state.biliPhase = .idle
                state.biliUname = ""
            },
            makeView: {
                AnyView(ContentView(initialRoute: .settings)
                    .environment(\.settingsPreviewScrollTarget, "settings-bili"))
            }
        ))

        // MARK: B 站扫码中

        scenes.append(.init(
            name: "settings-popover-bili-qr",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { state in
                state.mediaControlKeysEnabled = false
                state.biliPhase = .qrWaiting
                state.previewSetBiliQR("https://passport.bilibili.com/h5-app/passport/login/scan?navhide=1&qrcode_key=preview-bili")
            },
            makeView: {
                AnyView(ContentView(initialRoute: .settings)
                    .environment(\.settingsPreviewScrollTarget, "settings-bili"))
            }
        ))

        // MARK: 媒体键权限提示

        scenes.append(.init(
            name: "settings-popover-permission",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.mediaControlKeysEnabled = true
            },
            makeView: {
                AnyView(ContentView(initialRoute: .settings)
                    .environment(\.settingsForceMediaKeyWarning, true)
                    .environment(\.settingsPreviewScrollTarget, "settings-protection"))
            }
        ))

        // MARK: 底部: 缓存 / 账号 / 关于

        scenes.append(.init(
            name: "settings-popover-account",
            presentation: .popover(size: popoverSize),
            settleTime: 1.0,
            configure: { state in
                state.mediaControlKeysEnabled = false
            },
            makeView: {
                AnyView(ContentView(initialRoute: .settings)
                    .environment(\.settingsPreviewScrollTarget, "settings-account"))
            }
        ))

        // MARK: 设置页全览 (设计走查用: 372 宽完整内容, 不是真实窗口)

        scenes.append(.init(
            name: "settings-full",
            presentation: .window(PreviewWindowConfig(
                size: CGSize(width: DS.Size.popoverWidth, height: 1160),
                title: "设置 · 全览",
                styleMask: [],
                transparentTitlebar: false,
                opaque: false
            )),
            settleTime: 1.2,
            withShadow: false,
            configure: { state in
                state.mediaControlKeysEnabled = false
                state.biliPhase = .loggedIn
            },
            makeView: { AnyView(SettingsSpecPage()) }
        ))

        // MARK: 主窗口内容区宽度的设置页 (layout: .window)

        scenes.append(.init(
            name: "settings-window",
            presentation: .window(PreviewWindowConfig(
                size: CGSize(width: 788, height: 640),
                title: "设置",
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                transparentTitlebar: true,
                opaque: false
            )),
            settleTime: 1.1,
            configure: { state in
                state.mediaControlKeysEnabled = false
                state.biliPhase = .loggedIn
            },
            makeView: { AnyView(SettingsWindowPage()) }
        ))

        // MARK: 登录页各状态

        scenes.append(.init(
            name: "login-waiting",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { state in
                state.profile = nil
                state.loginPhase = .qrWaiting
                state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
            },
            makeView: { AnyView(LoginView().frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)) }
        ))

        scenes.append(.init(
            name: "login-scanned",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { state in
                state.profile = nil
                state.loginPhase = .qrScanned
                state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
            },
            makeView: { AnyView(LoginView().frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)) }
        ))

        scenes.append(.init(
            name: "login-logging-in",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { state in
                state.profile = nil
                state.loginPhase = .loggingIn
                state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
            },
            makeView: { AnyView(LoginView().frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)) }
        ))

        scenes.append(.init(
            name: "login-failed",
            presentation: .popover(size: popoverSize),
            settleTime: 1.1,
            configure: { state in
                state.profile = nil
                state.loginPhase = .failed("已授权，但获取用户信息失败，请重试")
                state.previewSetLoginQR("https://music.163.com/login?codekey=preview-8f3a2c")
            },
            makeView: { AnyView(LoginView().frame(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)) }
        ))

        // MARK: B 站网页登录窗口 (560×720)

        scenes.append(.init(
            name: "bili-web-login",
            presentation: .window(PreviewWindowConfig(
                size: CGSize(width: 560, height: 720),
                title: "哔哩哔哩 · 网页登录"
            )),
            settleTime: 2.2,
            configure: { _ in },
            makeView: { AnyView(BiliWebLoginView(previewMode: true)) }
        ))

        return scenes
    }
}

// MARK: - 走查用页面

/// 372 宽的设置页全览: 顶部一条最小页头 + 完整设置内容。
private struct SettingsSpecPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        AlbumTintProvider(url: state.currentCoverURL) {
            VStack(spacing: 0) {
                HStack(spacing: DS.Space.m) {
                    DSBrandMark(size: 15)
                    Text("设置")
                        .font(DS.TypeScale.navTitle)
                        .tracking(DS.Tracking.tight)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text("372 PT · FULL PAGE")
                        .font(DS.TypeScale.micro)
                        .tracking(DS.Tracking.micro)
                        .foregroundStyle(DS.Palette.textQuaternary)
                }
                .padding(.horizontal, DS.Space.popoverPadding)
                .frame(height: 42)

                SettingsView(layout: .popover)
            }
        }
    }
}

/// 模拟主窗口内容区: 页头 + `SettingsView(layout: .window)`。
private struct SettingsWindowPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        AlbumTintProvider(url: state.currentCoverURL) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(DS.Tracking.display)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("音质 · 输出 · 播放保护 · 账号")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .padding(.horizontal, DS.Space.windowPadding)
                .padding(.top, 36)
                .padding(.bottom, DS.Space.m)

                SettingsView(layout: .window)
            }
        }
    }
}
#endif
