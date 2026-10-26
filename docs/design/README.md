# 净听 · macOS 27 "Golden Gate" 视觉重设计

> 这不是一次换肤。我们把净听从"一个能用的 SwiftUI 面板"重做成"一款像 Apple 亲手做的 macOS 27 应用"：
> 玻璃有厚度、圆角同心、颜色只来自音乐本身、每个数字都是等宽的。

![总览](gallery/popover-home.jpg)

## 1. 设计立场

macOS 27 的 Liquid Glass 比 26 更克制：玻璃更"实"、可读性优先、圆角更紧、工具栏成组、侧边栏延伸到窗口边缘并带彩色图标。落到净听上，我们定下四条不可破的规则：

1. **玻璃是结构，不是装饰。** 只有"浮在内容之上"的层用 `glassEffect`：底部播放台、顶栏工具组、音质胶囊。列表、卡片、设置分组一律实体表面（深色白 5.5% / 浅色白 78% + 1px 描边）。这样在系统开启「降低透明度」时界面依然成立，也不会糊成一片。
2. **全局只有一束彩色光。** 强调色来自当前封面取样的「音乐色」(`@Environment(\.albumTint)`)，只出现在顶部氛围、进度条、选中态与主播放键上；其余全是黑白灰。主行动按钮（CTA）刻意保持高对比单色，避免跟随封面变脏。
3. **圆角同心递进。** 窗口 16pt（系统实测值）、面板 16、卡片 12、行 10、控件 8、徽标 6；嵌套时 `r_inner = r_outer − inset`，视觉上像一块玻璃被雕出来。系统窗口圆角由 macOS 自己绘制，我们只让内容同心。
4. **安静的动效。** 悬停/按下用系统 `interactiveSpring`，状态切换用 `snappy(0.28)`，页面切换用 `smooth(0.38)`；没有弹跳、没有循环闪烁。唯一的持续动画是"正在播放"的极轻波形，且遵循「减少动态效果」。

另外两条工程红线：

- **不复制系统 chrome。** 菜单栏 popover 的圆角、箭头、阴影全部交给 `NSPopover`；我们只负责内容。窗口红绿灯同理。
- **界面不读音频电平。** 净听的目标是让音乐从耳机里"直出"，波形只是呼吸感的装饰，不参与任何音频链路的处理或读取。

## 2. 视觉基础（`Sources/PureListen/Design/DesignSystem.swift`）

### 间距（4pt 网格）

| 令牌 | 值 | 用途 |
|---|---|---|
| `Space.xxs / xs / s / m / l / xl / xxl` | 2 / 4 / 6 / 8 / 12 / 16 / 20 | 组件内部节奏 |
| `Space.popoverPadding` | 16 | popover 内容边距（系统 popover 内容边距实测 16） |
| `Space.windowPadding` | 28 | 窗口内容边距 |

### 圆角

| 令牌 | 值 | 用途 |
|---|---|---|
| `Radius.window` | 16 | 窗口内容层（macOS 27 实测统一 16pt） |
| `Radius.panel` | 16 | 大面板 / 播放器底板 |
| `Radius.card` | 12 | 卡片、设置分组 |
| `Radius.row` | 10 | 列表行、内嵌分组 |
| `Radius.control` | 8 | 输入框、小控件 |
| `Radius.chip` | 6 | 徽标 |
| `Radius.art / artHero` | 12 / 18 | 封面 |

### 字阶

| 令牌 | 字号/字重 | 用途 |
|---|---|---|
| `heroTitle` | 26 semibold | 窗口大标题 |
| `sectionTitle / navTitle` | 15 semibold | 页面标题 |
| `rowTitle` | 13 medium | 列表主行 |
| `body` | 13 regular | 正文（系统 body） |
| `caption` | 11 regular | 说明 |
| `meta` | 10.5 medium | 元信息 |
| `micro` | 9 semibold，字距 +0.9，全大写 | "LOSSLESS · 44.1kHz" 类微标签 |
| `timecode` | 10.5 medium + `monospacedDigit` | 时间码 |

标题收紧字距 `-0.1 ~ -0.4`；中文不回退字号（PingFang SC 在 11/13pt 是系统标准）。

### 色彩

| 令牌 | 深色 | 浅色 |
|---|---|---|
| `canvas` | `#0E0E11`（墨黑） | `#F4F2EE`（暖纸） |
| `surface` | 白 5.5% | 白 78% |
| `surfaceHover` | 白 8.5% | 黑 4.5% |
| `surfaceSelected` | 白 12% | 黑 7% |
| `hairline` | 白 7.5% | 黑 7.5% |
| `textPrimary` | 白 94% | 黑 91% |
| `textSecondary` | 白 60% | 黑 58% |
| `textTertiary` | 白 38% | 黑 38% |
| `mint / amber / rose / accent` | 语义色，仅用于状态与唯一强调 | 同左 |

「音乐色」由封面取样（`AlbumPalette`）：缩到 24×24，取最饱和像素的色相为主、加权平均为辅，并把饱和度/亮度夹到可读区间；纯灰封面回退中性色。这样同一套 UI 在任意专辑下都不会脏。

### 动效

| 令牌 | 值 |
|---|---|
| `Motion.quick` | `.interactiveSpring()`（悬停/按下） |
| `Motion.standard` | `.snappy(duration: 0.28)`（状态切换） |
| `Motion.page` | `.smooth(duration: 0.38)`（页面/展开） |
| `Motion.press` | `.interactiveSpring(response: 0.18, dampingFraction: 0.72)` |
| `Motion.breathe` | 2.4s 呼吸（仅状态点） |

## 3. 组件（`Design/Components.swift`）

| 组件 | 说明 |
|---|---|
| `DSBrandMark` | 品牌标记：一张唱片（外圈 18° 开口）+ 中心点 |
| `DSChip` | 胶囊徽标，5 种语义 tone |
| `DSIconButton` | 圆形图标按钮，内置悬停玻璃 |
| `DSPillButton` | 胶囊按钮；`prominent` 为高对比单色（主行动） |
| `DSPlayButton` | 白色/黑色实心播放球（媒体应用的视觉锚点） |
| `DSSegmented` | 胶囊分段控件 + matchedGeometry 高亮 |
| `DSSeekBar` / `DSVolumeBar` | 细进度条（悬停加粗、拖动跟手、实时音量） |
| `DSWaveform` / `DSPlayingIndicator` | 装饰波形，遵循 Reduce Motion |
| `DSListRow` | 列表行（悬停、选中、左侧强调条） |
| `DSSettingRow` / `DSGlyphTile` | 设置行与彩色图标块 |
| `DSStatusDot` / `DSSoftDivider` / `DSEmptyState` / `DSSearchField` | 状态点 / 分隔线 / 空状态 / 搜索框 |
| `CoverArtwork` | 封面（圆角、描边、投影、占位符、异步加载） |
| `AlbumTintProvider` / `AlbumWash` | 封面取色与氛围背景 |
| `QRCodeView` | 白色二维码卡片（可选"已确认"浮层） |

## 4. 屏幕

### 菜单栏 Popover（372×588）

- **顶栏**：字标 + 上下文副标题；右侧两枚图标收进一枚玻璃胶囊（Golden Gate 的 toolbar cluster 语言）。
- **歌单 / 搜索 / B站**：胶囊分段控件切换；列表在底部玻璃播放台下方滚动穿过（`contentMargins` + `scrollEdgeEffectStyle`）。
- **快捷播放**：粘贴网易云链接/ID、B站 BV/链接、音频直链。
- **浮动播放台**：进度 + 时间码；封面 + 曲名 + 艺人·独占；上一首/播放/下一首；音量 + `44.1/16`、`无损`、`位完美`（非位完美时显示"数字衰减"）。它就是整个界面的玻璃时刻。

### 正在播放窗口（940×640，最小 820×560）

- 真实 `NSWindow`：隐藏标题栏、内容延伸到标题栏与侧边栏下方、可拖动窗口背景。
- **背景**：封面放大模糊 + 暗色遮罩 + 音乐色晕染；白字对比按 4.5:1 校验。
- **左侧 edge-to-edge 侧边栏**：品牌区、四项导航（正在播放 / 歌词 / 播放链路 / 设置）、底部输出设备与「独占输出 · 位完美」状态。
- **正在播放**：大封面 + 标题/艺人 + 音质徽标 + 进度 + 播放大键 + 音量 + "接下来"。
- **歌词**：逐行居中，当前行放大加粗，翻译紧随，点击跳转，顶部/底部渐隐。
- **播放链路**：音源 → 解码 → 缓冲 → 独占输出 → 设备 的竖向信号流，末尾一张"SRC 已消除 / 位完美"结论卡。
- **设置**：与 popover 共用 `SettingsView(layout: .window)`。

### 设置页

分组卡片：音质、输出设备、播放保护（接管全部输出/静音/媒体键/音量联动）、B 站账号、缓存、账号、说明与退出。全部使用系统原生 Toggle（mini switch），说明文字 11pt secondary，行高 32 起。

### 登录页

品牌标记 + 二维码白色卡片（已扫码时压暗并浮出对勾）+ 状态文案 + 失败重试；无封面时用品牌靛紫光晕。

### B 站网页登录窗口（560×720）

玻璃标题栏 + 圆角 WebView 卡片 + 完成按钮；保留原 Cookie 收割逻辑。

## 4.5 液态玻璃交互（指针透镜 / 液态选择）

对齐官方 Liquid Glass 的交互反馈（HIG「Materials」+ SwiftUI「Applying Liquid Glass to custom views」+ WWDC25「Meet Liquid Glass」+ 官方 Adopting Liquid Glass 演示视频）：

- **指针透镜**：玻璃控件按下时**原地整体放大**成一块玻璃透镜（不是压缩、更不是左右拉伸）：小圆钮/胶囊钮 ×1.20、分段控件的选中透镜胶囊 ×1.40。整条分段控件**不放大**，只有胶囊放大；胶囊允许越出轨道 8pt（"出框"感），但不会冒出弹窗。边缘用青/品红的色散高光与柔和光晕表现光折射，**不画任何脱离控件的白色光圈**。松手弹回原尺寸。实现见 `Design/GlassInteraction.swift`：用 `NSEvent` 本地监听跟踪指针（不安装手势、不拦截事件，点击/拖拽滑条完全不受影响），因此小圆钮、胶囊钮、分段条都能稳定看到官方那种"透镜跟着指针走"的效果。
- **液态分段选择**：分段控件不再用固定的静态选中片，而是把选中片做成跟随指针的液态胶囊 —— 按住时**只有选中胶囊整枚放大成一块凸起的玻璃透镜（×1.40，阴影加深）**并跟随指针移动，整条控件尺寸不变；放大后的胶囊会稍稍越出轨道（最多 8pt，不会冒出弹窗）；松手后回落到指针所在分段（与系统分段控件的"按拖选择"一致）。放大倍率来自 Apple 官方 Adopting Liquid Glass 演示视频的逐帧实测（系统控件按下时整枚玻璃大约放大 1.1~1.4 倍，透镜本体更明显）。轨道本身使用 `.glassEffect(.regular.interactive(), in:)`。
- **按 HIG 克制使用**：只有"控件"才加指针反馈；播放台、Bili 顶栏、登录/状态胶囊等**容器/状态展示**保持非交互玻璃，避免玻璃层互相干扰。
- **无障碍**：开启「降低透明度」时玻璃与透镜整体退化为实体填充，不产生动态光照。
- **可验收截图**：`--ui-studio --only glass-lens` 会用调试环境变量把指针"固定"在控件里，dark/light 各出一张，能看到整体放大后的透镜胶囊与跟随指针的位置。

## 5. 无障碍与系统适配

- **降低透明度**：`dsGlass` 自动退化为 `.ultraThinMaterial` + 实体填充；所有内容层级不依赖玻璃。
- **减少动态效果**：波形停止循环，只保留静态帧；页面切换改为淡入。
- **增强对比度**：文字色本身已按 WCAG 调校；语义色（mint/amber/rose）在深/浅色下分别选取可读亮度。
- **深浅色**：全部令牌由 `NSColor(name:dynamicProvider:)` 定义，跟随系统外观；每个屏幕都出 dark/light 两套截图验收。
- **菜单栏**：模板图标（template image）自动适配浅/深菜单栏；左键开面板，右键出原生菜单（当前曲目、播放/暂停、下一首、窗口、设置、退出）。

## 6. 工程与验收

```
Sources/PureListen/
  Design/          DesignSystem.swift, Components.swift, AlbumArtwork.swift, QRCodeView.swift
  Views/Popover/   根视图、路由、浏览列表、浮动播放台
  Views/Window/    主窗口：外壳、侧边栏、播放页、歌词页、链路页、设置页
  Views/Settings/  设置页卡片、B 站登录卡
  Views/SettingsView.swift, LoginView.swift, BiliWebLoginView.swift
  UIPreview/       无音频截图工作室（Debug 专用）
tools/shoot-screens.sh   一键重出全部截图
docs/research/           macOS 27 设计语言研究（855 行）+ SDK API 速查（1575 行）
```

### 截图（无音频）

```bash
swift build -c debug --product PureListen
caffeinate -u -t 2
.build/debug/PureListen --ui-studio --out docs/design/screens
```

`--ui-studio` 只在 Debug 构建中存在：它用假 `AppState`（`previewMode`，不枚举音频设备、不联网、不启轮询）把真实的 `NSPopover` / `NSWindow` 渲染出来，再用 `screencapture -l` 抓窗口。因此**整个设计验证过程不会发出任何声音**，也不需要登录。

### 研究依据

- `docs/research/macos27-design-language.md`：macOS 27 Golden Gate 设计语言研究（实测窗口圆角 16pt、popover ≈20pt、控制高度 20/24/28/36、字阶、玻璃透射与边缘配方、动效落定时间、菜单栏与工具栏尺寸）。
- `docs/research/sdk-api-cheatsheet.md`：macOS 27 SDK 设计相关 API 的可用性矩阵与可编译配方（`glassEffect` / `ConcentricRectangle` / `backgroundExtensionEffect` / `scrollEdgeEffectStyle` / AppKit 玻璃视图 / 状态栏会话）。
