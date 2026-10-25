# 净听 PureListen · macOS 27 视觉规范

> 目标：让净听看起来像 Apple 为 macOS 27 "Golden Gate" 亲自做的一款音乐应用 —— 安静、精确、有光。

## 设计立场

macOS 27 的 Liquid Glass 比 26 更克制：玻璃更"实"，可读性优先，圆角更紧，工具栏成组出现，侧边栏延伸到窗口边缘并带彩色图标。落到净听上：

1. **玻璃是结构，不是装饰。** 只有"浮在内容之上"的层用 `glassEffect`：播放控制台、分段切换、浮动工具组。列表、卡片、设置分组一律用实体表面（白 5.5% / 浅色模式白 78% + 细描边），这样 Reduce Transparency 时界面依然成立。
2. **全局只有一束彩色光。** 颜色来自当前封面取样的「音乐色」（`@Environment(\.albumTint)`）：只在顶部氛围晕染、进度条、选中态、主按钮上出现。其余一律黑白灰。没有第二种强调色。
3. **圆角同心递进。** 外层 18 / 卡片 14 / 行 10 / 控件 9 / 徽标 7。嵌套时用 `DS.Radius.inner(outer, inset:)`，视觉上像一块玻璃被雕刻出来。
4. **数字必须精确。** 所有 kHz / bit / 时间码用等宽数字（`DS.TypeScale.timecode`），音频参数是大写微标签（`dsMicroLabel()`，9pt semibold，字距 +0.9）。
5. **动效安静。** 只有悬停淡入、状态切换、播放键 morph。没有任何弹跳、没有循环闪烁。唯一持续动画是「正在播放」的波形（极轻）和状态点的呼吸。

## 基础令牌（只用令牌，不要写死数值）

```swift
DS.Space.xxs/xs/s/m/l/xl/xxl/xxxl          // 2 4 6 8 12 16 20 24
DS.Radius.panel/card/row/control/chip/art/artHero   // 18 14 10 9 7 12 18
DS.TypeScale.heroTitle/sectionTitle/navTitle/rowTitle/body/caption/meta/micro/timecode
DS.Tracking.display/micro/tight
DS.Palette.canvas/canvasElevated/surface/surfaceHover/surfaceSelected/hairline/
           hairlineStrong/textPrimary/textSecondary/textTertiary/textQuaternary/mint/amber/rose
DS.Motion.quick/standard/page/press
DS.Size.popoverWidth(372)/popoverHeight(588)/windowWidth(940)/windowHeight(640)/
        sidebarWidth(168)/rowHeight(44)/artRow(34)/controlHeight(28)
DS.Shadow.art/floating/panel
```

字体：SF Pro（系统默认）。标题收紧字距（`tracking(DS.Tracking.tight)`），微标签放开字距且全大写。

## 可用组件（`Design/Components.swift`）

| 组件 | 用途 |
|---|---|
| `DSBrandMark(size:tint:)` | 品牌标记（脉冲点 + 左右声波弧） |
| `DSSectionHeader(title:detail:trailing:)` | 分区标题 |
| `DSChip(text:systemImage:tone:compact:)` | 徽标；`tone`: `.neutral/.accent/.mint/.amber/.rose` |
| `DSIconButton(systemName:size:iconSize:isActive:help:action:)` | 圆形图标按钮（自带悬停） |
| `DSPillButton(title:systemImage:prominent:tint:action:)` | 胶囊按钮 |
| `DSPlayButton(isPlaying:size:action:)` | 主播放按钮（白色玻璃球） |
| `DSSegmented<Item>(items:title:selection:height:)` | 胶囊分段控件（matchedGeometry 高亮） |
| `DSSeekBar(progress:tint:height:showsThumbAlways:onScrub:onScrubbing:)` | 可拖进度条（悬停加粗） |
| `DSVolumeBar(volume:tint:onVolume:)` | 音量条 |
| `DSWaveform(isPlaying:tint:bars:barWidth:maxHeight:)` | 装饰波形（不读音频） |
| `DSPlayingIndicator(isPlaying:tint:)` | 列表内"正在播放"指示 |
| `DSListRow(title:subtitle:isSelected:height:action:leading:trailing:)` | 列表行 |
| `DSSettingRow(title:subtitle:systemImage:tint:trailing:)` | 设置行 |
| `DSGlyphTile(systemName:tint:size:)` | 彩色圆角图标块（侧边栏/设置） |
| `DSStatusDot(color:isLive:diameter:)` | 状态圆点 |
| `DSSoftDivider()` / `DSEmptyState(...)` / `DSSearchField(...)` | 分隔线 / 空状态 / 搜索框 |
| `AlbumTintProvider(url:intensity:showsWash:content:)` | 封面取色 + 氛围背景（每个屏幕的最外层） |
| `CoverArtwork(url:size:radius:shadow:borderOpacity:)` | 封面 |
| `AlbumPaletteStore.shared.palette(for:)` | 异步取色（一般不用手写，交给 Provider） |

修饰符：`.dsSurface(radius:fill:stroke:)`、`.dsGlass(in:tint:interactive:fallbackFill:)`、`.dsHover(...)`、`.dsPressable()`、`.dsHairline(radius:)`、`.dsShadow(DS.Shadow.art)`、`.dsMicroLabel(color:)`、`.dsAppearance(tint:)`。

## 屏幕规格

### A. 主窗口「正在播放」（940×640，独立 NSWindow）

- 真实 NSWindow：`styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`，`titlebarAppearsTransparent = true`，`titleVisibility = .hidden`，`isMovableByWindowBackground = true`，内容延伸到标题栏与侧边栏下方（`backgroundExtensionEffect()`）。最小尺寸 820×560。
- **背景**：放大 1.35×、`blur(radius: 60)` 的封面铺满 + 黑色 30% 遮罩 + 一层 `AlbumWash`（`showsWash: true`）。背景不能抢文字。
- **左侧边栏（168pt，edge-to-edge，延伸到窗口左边缘与顶部）**：
  - 顶部留 52pt 给红绿灯（窗口按钮浮在其上，不要在 SwiftUI 里画按钮）。
  - 品牌区：`DSBrandMark(size: 18)` + "净听"（13 semibold）。
  - 导航项（图标 + 文字，行高 32，圆角 9）：正在播放 / 歌词 / 播放链路 / 设置。选中态 = 玻璃胶囊或 `tint.opacity(0.16)` + 文字 tint；图标用 `DSGlyphTile(size: 20)` 或 16pt symbol。`matchedGeometryEffect` 做滑动高亮。
  - 底部：输出设备名 + 采样率（`dsMicroLabel`），以及 `DSStatusDot` + "独占输出 / 位完美"。
- **内容区**：
  - 正在播放：居中大封面（260–300，`Radius.artHero`，投影 `DS.Shadow.art`）；标题 26 semibold 收紧字距；艺人 13 secondary；一行徽标（无损 / 44.1kHz·16bit / FLAC / 位完美）；进度条 + 两端时间码；播放控制（上一首 20pt / `DSPlayButton(size: 56)` / 下一首 20pt，可加随机/循环图标）；音量行（`DSVolumeBar`，宽度 ≤ 320）。整个内容区顶部留 40pt 避开标题栏。
  - 歌词：占满内容区，逐行居中；当前行 22 semibold `textPrimary`，其余 15 `textSecondary.opacity(0.5)`；翻译 12（当前行 0.75 透明）；点击行跳转；滚动到中心（`scrollTo(anchor: .center)`），切换歌曲时重置；顶部/底部加渐变遮罩让首尾行淡出。空歌词用 `DSEmptyState`。
  - 播放链路：竖向信号流。节点卡片（高 52）依次：音源 → 解码 → 缓冲 → 独占输出 → 设备；每个节点：左 `DSGlyphTile`，标题 + 灰色细节（采样率/位深/缓冲百分比），右侧状态（✓ 或数值）。节点之间用 16pt 连接线 + 小圆点（成功 mint；降采样 amber）。底部一张结论卡：SRC 是否消除 / 位完美，用 `DSChip`。缓冲百分比可用 `TimelineView(.periodic(0.5))` + `state.player.ringStats()`。
  - 设置：直接嵌入 `SettingsView(layout: .window)`（由 Settings 负责人实现），宽度自适应。
- 窗口右上角浮一个玻璃胶囊显示当前音质摘要（`dsGlass(in: Capsule())`）。

### B. 菜单栏 Popover（372×588，由 Lead 负责）

顶部状态条 → 分段切换 → 内容列表 → 底部浮动玻璃播放台。列表在播放台下方滚动（内容从玻璃下穿过）。设置页与登录页由 Settings/Login 负责。

### C. 设置页（`SettingsView(layout:)`）

- 两种布局：`.popover`（372 宽，单列卡片，卡片圆角 `Radius.card`，内边距 12）与 `.window`（宽内容区，卡片 maxWidth 620 居中或左对齐，行距更松）。
- 结构（每张卡片一个 `.dsSurface`）：
  1. 音质：`DSSegmented`（Hi-Res / 无损 / 极高 / 标准，用 `NCLevel.label`），下方说明文字 11pt secondary。
  2. 输出：设备 `Picker`（自动 + 各设备，菜单样式即可）；"启动时自动继续上次歌单" switch。
  3. 播放保护：接管全部输出设备 / 播放期间系统静音 / 接管媒体键（+ 无权限时 amber 提示）/ 系统音量联动。全部用**系统原生 Toggle(.switch, .mini)**，右侧对齐。
  4. 哔哩哔哩账号：已登录显示用户名 + 退出；未登录显示"网页登录（推荐）/ 扫码登录"两个 `DSPillButton`；扫码中显示 `QRCodeView`（可复用 `UIPreview` 之外新写的组件）+ 状态文案 + 取消。
  5. 缓存：大小 + 清除按钮。
  6. 账号：网易云昵称 + 退出登录（rose 色）。
  7. 底部说明文字（11pt secondary，行距 3）+ "退出净听"（rose 描边胶囊）。
- 页头用呼出方（popover/window）提供，不在 `SettingsView` 内画返回按钮。

### D. 登录页（`LoginView()`，作为 popover 内容）

- 外层 `AlbumTintProvider(url: "", intensity: 1)`（无封面时用中性色 + 品牌渐变 `Color(hex: 0x6E5BFF)` → `Color(hex: 0x1B2A6B)` 柔和光晕）。
- 居中：`DSBrandMark(size: 40)`；标题 "净听" 22 semibold；副标题 "网易云音乐 · 无损独占输出" 12 secondary。
- 二维码放在白色圆角卡片里（radius 14，padding 10，白色 96% 底，柔和投影），尺寸 176；`qrScanned` 时在卡片上加 tint 色勾选浮层 + "已确认" 文案。
- 状态行：等待时 "打开网易云音乐 App 扫码登录"（12 medium）；已扫 "已在手机上确认，正在登录…"（tint）；`loggingIn` 时 ProgressView + 文案；失败时 amber 图标 + 错误文本 + "重新扫码"/"重试获取账号" 两个按钮。
- 底部一行小字：11 tertiary，"登录后即可拉取歌单并以无损音质独占输出到耳机孔"。

### E. B 站网页登录窗口（`BiliWebLoginView()`，560×720）

- 玻璃标题栏（高 44）：返回/标题"哔哩哔哩 · 网页登录" + 右侧"完成"胶囊按钮；下方 WKWebView 圆角 12 裁切，四周留 12 内边距，卡片描边。
- 背景 `AlbumWash` + canvas；窗口 `titlebarAppearsTransparent` 由调用方设置。

## 视觉红线（Do / Don't）

- ✅ 用令牌；卡片 14、行 10、微标签 9pt 大写；单色强调。
- ✅ 列表行悬停用白 8.5%，选中用 tint 13%；不要用系统蓝。
- ✅ 玻璃只压在内容/封面上；不要在玻璃上再叠玻璃（同一视觉层级最多一层）。
- ✅ 文字对比度：dark 模式正文至少 `textPrimary(0.94)`；secondary 只用于辅助信息。
- ❌ 不要用 `GroupBox`、`.roundedBorder` TextField、`.buttonStyle(.link)`、`Picker(.segmented)`、系统蓝强调色 —— 这些是旧版痕迹。
- ❌ 不要给设置项加大色块；不要多色渐变按钮；不要阴影堆叠。
- ❌ 不要播放任何音频、不要碰 CoreAudio、不要联网做测试。

## 预览与验收

```bash
cd /Users/halo/dsharness/PureListen
swift build -c debug --product PureListen            # 各自用独立 scratch path, 见任务说明
.build/debug/PureListen --ui-studio --out docs/design/screens --only <场景名>
```

`--ui-studio` 是 Debug 专用的无音频截图模式：用假 AppState 把真实 NSPopover/NSWindow 渲染出来再抓图，`docs/design/screens/*-dark.png` / `*-light.png`。每次改完必须自己看图（用 read_image 打开），至少改到 3 轮。

每个实现的文件必须自带 preview scenes（写在各自的 `UIPreview/Catalog+*.swift` 里），供 Lead 汇总截图。
