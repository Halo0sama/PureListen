# 设置页 / 登录页 / B站网页登录 —— 实现说明

## 文件

| 文件 | 内容 |
|---|---|
| `Sources/PureListen/Views/SettingsView.swift` | `SettingsLayout` + `SettingsView` 主体（音质 / 输出 / 播放保护 / B站 / 缓存 / 账号 / 关于退出）。自带内部 `ScrollView`。 |
| `Sources/PureListen/Views/Settings/SettingsChrome.swift` | 设置页排版度量与 UI 原语：`SettingsMetrics`、`SettingsSection(+Header)`、`SettingsCard`、`SettingsRow`、`SettingsRowDivider`、`SettingsFootnote`、`SettingsToggle`(DSSwitch)、`SettingsSmallButton`、`SettingsDangerButton`、`SettingsSurface`(window 实体表面)、截图用环境开关。 |
| `Sources/PureListen/Views/Settings/SettingsBiliCard.swift` | B 站账号卡片四态：已登录 / 选择登录方式 / 扫码中（二维码 + 已扫胶囊 + 返回）/ 失败重试。 |
| `Sources/PureListen/Views/LoginView.swift` | 网易云扫码登录页：品牌光 + 声波标记 + 白色二维码卡 + 状态区（等待 / 已确认胶囊 / 登录中 / 失败重试）。 |
| `Sources/PureListen/BiliWebLoginView.swift` | 560×720 网页登录窗口：unified glass toolbar（与红绿灯同排，左留 78pt）+ 圆角 WKWebView 卡片 +「完成」主动收割 Cookie。DEBUG 提供 `previewMode` 本地占位页（不联网）。 |
| `Sources/PureListen/UIPreview/Catalog+Settings.swift` | 截图场景注册。 |

## 接口约定

- `SettingsView` 不画背景、不画页头/返回按钮；背景由 `AlbumTintProvider` 提供，页头由 popover 顶栏 / 窗口提供。
- `.popover`：宽 372，卡片撑满（左右 14pt 页边距），内容底部保留 138pt 给浮动播放台（内容从玻璃下穿过）。
- `.window`：卡片 maxWidth 620 左对齐、左右 28pt 页边距、行更松（行内 16pt / 行间 11pt）、卡片使用不透明实体表面（`SettingsSurface.solid`）保证在封面氛围上明确"浮"起。**已在窗口内由 `WindowSettingsPage` 直接嵌入，不要在外层再套 ScrollView 或水平 padding。**
- 页内唯一彩色是固定品牌色 `DS.Palette.brandAccent`：音质 chip、自绘 `DSSwitch` 开态、菜单 Picker tint；语义色只用 mint（状态点）/ amber（权限提示）/ rose（退出登录）。开关不使用系统强调色、不随封面变色。

## 截图场景（`--only <前缀>`）

- 生产形态：`settings-popover`、`settings-popover-bili`、`settings-popover-bili-qr`、`settings-popover-permission`、`settings-popover-account`、`settings-window`、`login-waiting`、`login-scanned`、`login-logging-in`、`login-failed`、`bili-web-login`。
- 设计走查专用（**不要进最终 gallery**）：`settings-full`（372 宽整页平铺，预览状态全 off）。

## 待 Lead 处理的遗留项

1. `REVIEW-1` P0-3 对比度：`DesignSystem.swift` 里 `Palette.textSecondary`（light alpha 0.58）在 11–12pt 下略低于 4.5:1，建议调至 0.66–0.70；本任务不修改共享 Design/ 文件。
2. `REVIEW-1` P1-6 页头齿轮：设置页上的 `gearshape` 按钮来自 `PopoverTopBar`（Lead 文件），建议在该路由下隐藏或改为返回/完成。
3. 截图工具：`UIPreviewStudio` 若改用 `.regular` 激活策略，会在 `screencapture` 前 `orderFrontRegardless()` 触发 `_NSPopoverWindow canBecomeMainWindow` 断言（lldb 已确认）；保持 `.accessory` 即正常。
