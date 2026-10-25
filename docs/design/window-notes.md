# 主窗口「正在播放」实现说明

> 代码: `Sources/PureListen/Views/Window/` · 场景: `UIPreview/Catalog+Window.swift`
> 截图: `.build-window/debug/PureListen --ui-studio --out docs/design/screens --only window`

## 结构

```
NowPlayingWindowView            // 根: AlbumTintProvider(showsWash: false) + 键盘快捷键
└─ WindowShell                  // ZStack: 氛围背景 / [侧边栏 + 内容区] / 浮动音质胶囊
   ├─ WindowAmbientBackground   // 模糊封面 + 遮罩 + 音乐色光晕 + 暗角
   ├─ WindowSidebar (168)       // 品牌 / 四项导航 / 设备与独占状态
   ├─ WindowContentArea         // 页面切换(透明度过渡)
   │  ├─ WindowHeroPage         // 大封面页
   │  ├─ WindowLyricsPage       // 逐行歌词
   │  ├─ WindowSignalPage       // 端到端信号流
   │  └─ WindowSettingsPage     // 内嵌 SettingsView(layout: .window)
   └─ WindowQualityCapsule      // 右上角玻璃胶囊(dsGlass, 唯一玻璃层)
```

窗口本身由 `NowPlayingWindowController` 创建: 940×640, `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`, 透明标题栏 + 隐藏标题, `isMovableByWindowBackground`, min 820×560, frame autosave。

## 三条视觉决定

1. **两层材质, 一条光。** 背景是唯一"有颜色"的层(模糊封面 + 音乐色光晕); 内容层全部实体表面; 玻璃只有右上输出状态胶囊一层。侧边栏用 `ultraThinMaterial` + 压暗渐变, 是 chrome 而非内容。浅色模式下氛围层在顶部渐隐, 内容区回到中性纸白。
2. **对比度优先。** 深色模式背景压到标题区亮度 ≈0.14(白字对比 ≈5.4:1); 顶部 0.36 → 底部 0.62 的黑色线性遮罩 + 内容列径向压暗。浅色模式用白色遮罩把封面变成暖纸底, 正文用 `textPrimary`。
3. **字号即层级。** 26 semibold 曲名(-0.4 字距) / 13 secondary 艺人 / 9pt 大写微标签 / 等宽时间码; 全大写只出现在微标签与英文品牌字。

## 信息分工(REVIEW-1 P1-5)

- 封面下徽标行 = **格式**(无损 / 44.1 kHz · 16 bit / FLAC);
- 右上玻璃胶囊 = **输出链状态**(`● 独占输出 · 位完美`);
- 侧边栏底部 = **设备**(输出设备 / 外置耳机 / 44.1 kHz · 自动跟随)。
三处各说一件事, 不再重复。

## 数据与交互

- 全部来自 `@EnvironmentObject state: AppState`: `trackStatus`、`playerState`、`player.bitPerfect`、`player.ringStats()`、`lyrics`/`lyricIndex`、`devices`/`selectedDevice`、`volume`。
- `seek(to:)` 拖动进度; 歌词行点击跳转; 上下曲/播放暂停直连 `playPrevious/playNext/playPause`。
- 键盘: 空格播放/暂停, ←/→ ±10s, ⌘←/⌘→ 上/下一首(窗口级 `keyboardShortcut`)。
- 播放链路页用 `TimelineView(.periodic(0.5))` 刷新环形缓冲百分比; 其余页面静态。
- 窗口缩到 820×560 时封面页自动切紧凑排版(收小封面、减间距、隐藏"接下来"行)。

## 已知边界

- `SettingsView(layout: .window)` 自带滚动与 28pt 留白, 窗口只提供页头, 不再包 ScrollView。
- 预览里窗口实际内容高度会因 PreviewStudio 建窗方式略有出入(页面本身用 GeometryReader 自适应, 不依赖固定高度)。
- 输出状态胶囊在未播放时隐藏; 设置页不显示胶囊。
- 设置页内容区先铺一层向下回到中性 canvas 的压暗层(卡片是半透明表面, 避免透出封面洗色), 并统一 `.tint(albumTint)`, 原生控件强调色跟随音乐色。
- 窗口出现时用 `WindowActivationView` 把 App 与窗口带到前台 —— 真实使用与截图模式共用; 否则 macOS 会把开关等原生控件画成非活动窗口样式(ON 态发灰)。
