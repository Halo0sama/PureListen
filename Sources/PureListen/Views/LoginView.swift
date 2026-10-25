import AppKit
import SwiftUI
import PureListenCore

// MARK: - 网易云扫码登录页
//
// 作为菜单栏 popover 的整个内容(未登录时替换掉主界面)。
// 视觉: 一束品牌柔光 + 极简声波标记 + 一张纯粹的白色二维码卡片。
// 仪式感来自留白与光, 不来自装饰。

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    /// 品牌紫: 与开关 / 选中态共用的固定品牌色, 不随封面变化。
    private var brandTint: Color { DS.Palette.brandAccent }

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        AlbumTintProvider(url: "", intensity: 1) {
            ZStack {
                background
                VStack(spacing: 0) {
                    Spacer(minLength: DS.Space.xl)
                    brandBlock
                        .padding(.bottom, DS.Space.xxl)
                    qrBlock
                    statusBlock
                        .padding(.top, DS.Space.l)
                    Spacer(minLength: DS.Space.l)
                    footBlock
                    Spacer(minLength: DS.Space.xl)
                }
                .padding(.horizontal, DS.Space.xxxl)
            }
            .environment(\.albumTint, brandTint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            // 真实运行时兜底: 若还没有发起过二维码轮询就补一次; 截图模式不碰网络。
            guard !isCaptureMode else { return }
            if state.loginPhase == .idle && state.loginQRURL == nil {
                state.startLoginPolling()
            }
        }
        .animation(DS.Motion.standard, value: state.loginPhase)
    }

    // MARK: - 背景光

    private var background: some View {
        ZStack {
            // 顶部一束品牌紫光。
            RadialGradient(
                colors: [
                    brandTint.opacity(isDark ? 0.50 : 0.15),
                    Color(hex: 0x1B2A6B).opacity(isDark ? 0.34 : 0.07),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.04),
                startRadius: 0,
                endRadius: isDark ? 380 : 320
            )
            // 自上而下的极淡高光, 让顶部像有一层光落下来。
            LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.055 : 0.45), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
            // 底部压暗, 让二维码卡片浮起来。
            LinearGradient(
                colors: [.clear, Color.black.opacity(isDark ? 0.22 : 0.025)],
                startPoint: UnitPoint(x: 0.5, y: 0.45),
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - 品牌

    private var brandBlock: some View {
        VStack(spacing: 0) {
            ZStack {
                // 两层声波涟漪, 与品牌标记的弧线呼应。
                Circle()
                    .strokeBorder(ringColor(0.075), lineWidth: 1)
                    .frame(width: 118, height: 118)
                Circle()
                    .strokeBorder(ringColor(0.045), lineWidth: 1)
                    .frame(width: 88, height: 88)
                DSBrandMark(size: 40, tint: DS.Palette.textPrimary)
                    .shadow(color: brandTint.opacity(isDark ? 0.55 : 0.30), radius: 20)
            }
            .frame(height: 120)

            Text("净听")
                .font(.system(size: 22, weight: .semibold))
                .tracking(DS.Tracking.display)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.top, DS.Space.m)

            Text("网易云音乐 · 无损独占输出")
                .font(.system(size: 11.5, weight: .regular))
                .tracking(0.2)
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.top, DS.Space.xs)
        }
    }

    private func ringColor(_ opacity: Double) -> Color {
        isDark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
    }

    // MARK: - 二维码

    private var qrBlock: some View {
        ZStack {
            // 卡片背后的一团品牌光晕。
            RoundedRectangle(cornerRadius: DS.Radius.card + 18, style: .continuous)
                .fill(brandTint.opacity(isDark ? 0.30 : 0.14))
                .frame(width: 200, height: 200)
                .blur(radius: 28)
                .allowsHitTesting(false)

            QRCodeView(content: state.loginQRURL ?? "",
                       size: 176,
                       scanned: false,
                       tint: brandTint)
        }
    }

    // MARK: - 状态

    private var statusBlock: some View {
        VStack(spacing: DS.Space.m) {
            switch state.loginPhase {
            case .qrWaiting:
                statusLines(title: "打开网易云音乐 App 扫码登录",
                            detail: "扫码后在手机上确认即可")
            case .qrScanned:
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("已在手机上确认，正在登录…")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(DS.Palette.mint)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .dsGlass(in: Capsule(style: .continuous),
                         tint: DS.Palette.mint.opacity(0.28))
            case .loggingIn:
                HStack(spacing: DS.Space.s) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text("正在获取账号信息…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            case .failed(let message):
                VStack(spacing: DS.Space.m) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(message)
                            .font(.system(size: 11))
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(DS.Palette.amber)

                    HStack(spacing: DS.Space.m) {
                        DSPillButton(title: "重新扫码") { state.startLoginPolling() }
                        DSPillButton(title: "重试获取账号", prominent: true) {
                            Task { await state.retryAccountOnly() }
                        }
                    }

                    if state.hasMusicU {
                        Text("登录凭证已就绪，只需重新获取账号信息")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
            default:
                HStack(spacing: DS.Space.s) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text("正在获取二维码…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
    }

    private func statusLines(title: String, detail: String) -> some View {
        VStack(spacing: DS.Space.xs) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary.opacity(0.92))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    // MARK: - 页脚

    private var footBlock: some View {
        VStack(spacing: DS.Space.m) {
            Text("登录后即可拉取歌单，并以无损音质独占输出到耳机孔")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("PureListen · Bit-perfect output")
                .font(DS.TypeScale.micro)
                .tracking(DS.Tracking.micro)
                .textCase(.uppercase)
                .foregroundStyle(DS.Palette.textQuaternary)
        }
    }

    // MARK: - 截图模式

    private var isCaptureMode: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--ui-studio")
        #else
        false
        #endif
    }
}
