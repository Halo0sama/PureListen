import SwiftUI
import PureListenCore

// MARK: - 哔哩哔哩账号卡片
//
// 四种状态: 已登录 / 未登录(选择登录方式) / 扫码中 / 失败。
// 扫码时二维码复用 Design/QRCodeView, 保持与登录页一致的白色实体卡片。

struct SettingsBiliCard: View {
    @EnvironmentObject var state: AppState
    var metrics: SettingsMetrics

    var body: some View {
        Group {
            switch state.biliPhase {
            case .loggedIn:
                loggedInRow
            case .qrWaiting, .qrScanned:
                scanning
            case .failed(let message):
                failed(message)
            case .idle:
                chooser
            }
        }
        .animation(DS.Motion.standard, value: state.biliPhase)
    }

    // MARK: 已登录

    private var loggedInRow: some View {
        SettingsAccountRow(avatarURL: state.biliAvatarURL,
                           name: state.biliUname.isEmpty ? "已登录" : state.biliUname,
                           service: "哔哩哔哩", metrics: metrics) {
            SettingsDangerButton(title: "退出登录", systemImage: "rectangle.portrait.and.arrow.right") {
                state.logoutBili()
            }
        }
    }

    // MARK: 未登录: 两种登录方式

    private var chooser: some View {
        SettingsAccountRow(avatarURL: "", name: "未登录", service: "哔哩哔哩", metrics: metrics) {
            HStack(spacing: DS.Space.s) {
                SettingsSmallButton(title: "网页登录", systemImage: "safari") {
                    state.onOpenBiliWebLogin?()
                }
                SettingsSmallButton(title: "扫码", systemImage: "qrcode") {
                    state.startBiliLogin()
                }
            }
        }
    }

    // MARK: 扫码中

    private var scanning: some View {
        VStack(spacing: DS.Space.l) {
            QRCodeView(content: state.biliQRURL ?? "", size: 132,
                       scanned: false,
                       tint: DS.Palette.mint)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            if state.biliPhase == .qrScanned {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("已扫码，请在手机上确认")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DS.Palette.mint)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .dsGlass(in: Capsule(style: .continuous),
                         tint: DS.Palette.mint.opacity(0.30))
            } else {
                Text(statusText)
                    .font(metrics.subtitleFont)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Button {
                state.cancelBiliLogin()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                    Text("返回其他登录方式")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.l)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .transition(.opacity)
    }

    private var statusText: String {
        switch state.biliPhase {
        case .qrScanned: return "已扫码，请在手机上确认"
        default: return "用哔哩哔哩 App 扫码登录"
        }
    }

    // MARK: 失败

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(message)
                    .font(metrics.footnoteFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
            .foregroundStyle(DS.Palette.amber)

            HStack(spacing: DS.Space.m) {
                DSPillButton(title: "改用网页登录", prominent: true) {
                    state.onOpenBiliWebLogin?()
                }
                DSPillButton(title: "重试扫码") {
                    state.startBiliLogin()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
    }
}
