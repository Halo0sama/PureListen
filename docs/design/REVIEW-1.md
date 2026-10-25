# REVIEW-1 · macOS 27 "Golden Gate" 设计评审

**评审对象：** 当前 `main` 工作树（HEAD `56b1401`，含未提交改动）在 `--ui-studio` 下的真实系统渲染 —— **50 张截图**（25 个场景 × 深/浅色）。
**截图快照：** 评审时的 50 张截图快照未入库（每张 0.5–1 MB，仓库体积考虑）；可用 `tools/shoot-screens.sh` 一键复现当前版本的同等场景。评审结论只依赖场景本身，不依赖快照文件。
**截图时间：** 2026-10-26 02:19–02:20 CST（`caffeinate -u` 防休眠；`screencapture -l` 抓真实 NSPopover / NSWindow）。
**对照标准：** `docs/research/macos27-design-language.md`（855 行，macOS 27 实测设计 brief）+ 本任务三条红线（单一主色 / 玻璃只用于 chrome 层 / 对比度）。
**方法：** 每张 PNG 均用 `read_image` 逐张查看后才下结论；颜色/对比度/面板尺寸用 Pillow + numpy 采样（WCAG 相对亮度），蓝色像素用色彩过滤统计；不确定项在 §4 单独标出。悬停/按下/动画等瞬态不在截图范围内，未评审。

---

## 1. 总评

**已经做对的（保留）：**

1. **外壳几何正确。** 普通 popover 面板实测 **372.0 × 588 pt**（22 个场景一致）；主窗口实测 **940 × 640 pt**；窗口圆角、edge-to-edge 侧边栏、透明标题栏都符合 Golden Gate（`window-hero-dark.png` 侧边栏一直通到窗口顶边，`settings-full-dark.png` 是 372 宽全页规格）。
2. **结构语言统一。** 设置页的分组卡片、胶囊分段控件、24pt 开关行、10.5pt 等宽时间码、SF Symbols 图标、单一字体 ramp 都已落地；`window-signal-dark.png` 的节点卡片 + mint 成功态是当前最"Apple"的一屏。
3. **玻璃层级基本正确。** 播放台浮在内容之上、内容从玻璃下穿过（`popover-home-*`）；卡片/列表用实体表面而不是玻璃 —— 这条红线守住了。

**系统性问题（本轮重点）：**

- **A. 主色失控：** 系统蓝（开关 #3C7FF4，chrome 内 2.2k–3.3k 像素/屏）与封面暖色、mint、rose、粉色 VIP 徽标同时出现；"全局只有一束彩色光"没有真正成立。
- **B. 封面氛围洗色过强、缺少中性底：** 浅色模式背景从 #F3EFEC 一路变成 **#D2CDC8（米灰）**，深色模式从 **#412F28（棕）** 到 #151012；直接后果是次级文字对比度集体不达标（见 P0-3）。
- **C. 信息密度/重复：** 播放台 120pt 高塞 3 行（进度+曲目+音量/徽标）；窗口顶部质量胶囊与封面下徽标重复；登录页说明文字与版权行堆叠；设置页"关于"4 行段落 + 3 个玫瑰色危险按钮。

---

## 2. 优先修改清单（15 条，按优先级排序）

> 每条 = 现象（含实测数字）→ 证据截图 → 具体改法 → 验收标准。
> 路径均相对 `docs/design/screens/review-1/`。

### P0 — 违反红线，先修

**P0-1 · 系统蓝开关遍布设置页（单一主色红线）**
- 现象：设置页所有 `Toggle(.switch)` 打开态是系统蓝，实测色 **#3C7FF4**；深/浅色都有。chrome 内蓝色像素统计：`settings-popover-dark.png` 2,240 px、`settings-popover-permission-dark.png` 3,349 px、`settings-window-dark.png` 2,218 px / light 2,257 px、`window-settings-dark.png` 3,337 px。`gallery-*.png` 的进度条/音量条也是系统蓝（4,862 / 5,698 px）。
- 证据：`settings-popover-dark.png`、`settings-popover-permission-light.png`、`settings-window-dark.png`、`window-settings-dark.png`、`gallery-light.png`。
- 改法：对 Form / Toggle / DSSegmented / 进度条统一 `.tint(albumTint)`（无封面时 fallback 到 **中性灰白**，不要 `Color.accentColor`）；`DS.SeekBar/DSVolumeBar` 的默认 tint 从 `.accentColor` 改为 `albumTint`；`MarkTest` 里 48pt 的 `.accentColor` 同样改掉。
- 验收：对全屏截图跑蓝色过滤（见附录 A 脚本），chrome 区域 `#007AFF/#0A84FF` 家族像素 = 0；仅封面/网页内容允许彩色。

**P0-2 · 登录页 popover 高度失控 + 顶部露出桌面/接缝**
- 现象：`login-waiting-*`、`login-scanned-*`、`login-failed-*`、`login-logging-in-*` 的面板高 **895 pt**（含箭头 906.5 pt），比规格 588 pt **高 52%**；顶部约 300pt 是空的玻璃区，透出桌面（浅色下是 #3E3E3E 灰块 + 右侧模糊窗口），有明显水平接缝。同一登录页在主 catalog 的 `popover-login-dark.png` 里是正常 372×588。
- 证据：`login-waiting-dark.png`（964×2210 px）、`login-scanned-light.png`、`popover-login-dark.png`（1188×1320 px，正常）。
- 改法：登录内容固定 `frame(width: 372, height: 588)` 且内部用 `ScrollView` 兜底；`NSHostingController.preferredContentSize = 372×588` 后再赋给 `NSPopover`；预览场景改用 `ContentView()` 路由（与主 catalog 一致）而不是直接嵌 `LoginView()`。若为场景问题，至少保证 `preferredContentSize` 在赋值 `contentViewController` **之后**设置。
- 验收：登录四态截图面板 body = **588 ± 1 pt**；无桌面透出、无接缝。

**P0-3 · 浅色模式次级文字对比度不达标（对比度红线）**
- 现象（WCAG 实测）：
  - 头部副标题（"网易云 · Halo"）light **2.29:1**（#8B807A on #D5C5BB）、dark **3.56:1**（#7F7570 on #2E1E19）→ 11pt 需 ≥4.5:1，两模式都不达标。
  - 歌曲行艺人副标题 light **3.84:1**（#68625F on #DACCC2）。
  - 设置页行说明 light **4.28:1**（#747474 on #F7F4F2，12pt）边缘不合格。
  - 正在播放行（tracks）dark 强调文字 **3.38:1**（#9E6140 on #291C17，13pt semibold）不合格。
- 证据：`popover-home-light.png`、`popover-tracks-dark.png`、`popover-settings-light.png`。
- 改法：① 先把背景洗色降下来（P1-1），这一步就能把以上数值整体抬 0.8–1.5；② `DS.Palette.textSecondary` 浅色 alpha 0.58 → **0.66–0.70**、深色 0.60 → 0.66；③ 强调文字用"albumTint 混 30% textPrimary"并 clamp 亮度；④ 10pt 仅留时间码/单位，副标题最低 11pt。
- 验收：用附录 A 的对比度脚本复查 4 处，全部 ≥4.5:1。

### P1 — Golden Gate 观感与信息层级

**P1-1 · 封面氛围色覆盖整屏，浅色变"米色 App"**
- 现象：浅色模式画布顶部 #F3EFEC → 底部 **#D2CDC8**；深色 #412F28 → #151012。列表没有中性表面，文字直接坐在洗色上；浅色模式整体读作"2021 渐变米色 app"，不是 macOS 27 的中性底 + 局部氛围。
- 证据：`popover-home-light.png`、`popover-tracks-light.png`、`window-hero-light.png`。
- 改法：`AlbumTintProvider` 的 wash 改为**顶部 40% 的局部渐隐层**（mask 到 .clear），峰值 opacity 深色 ≤0.20 / 浅色 ≤0.10；内容区回到 `DS.Palette.canvas`（深 #0E0E11 / 浅 #F4F1EC 附近），列表行/卡片用 `DS.Palette.surface`；窗口背景同理，封面模糊层保留但压到 0.2 以下。
- 验收：截图取样"画布底部"应与 canvas 色相差 ≤2%（当前浅色差 8%+）。

**P1-2 · 播放台 120pt 塞 3 行 + 3 个徽标，拥挤且抢内容**
- 现象：播放台高度 ≈**112 pt**（实测内容区 y≈470→583.5；左/右内缩 9.5/11 pt、底部几乎贴边 2 pt；内部 3 行 = 进度/时间、曲目+传输、音量+3 徽标）；588pt 的 popover 被占掉约 19%，底部左右圆角外侧还漏出列表行。
- 证据：`popover-home-dark.png`、`popover-home-light.png`、`popover-tracks-dark.png`。
- 改法：合并为 2 行、整条高 **≤96 pt**：第 1 行 = 封面缩略图 + 曲名/艺人 + 传输（⏮▶⏭）；第 2 行 = 进度条 + 两端时间。**移除音量行**（popover 里用系统音量/菜单即可）与"数字衰减"徽标；徽标最多 1 个（"无损"），"44.1/16"并入副标题文本。
- 验收：播放台高度 ≤96pt；可见徽标 ≤1 个。

**P1-3 · 播放行三重视觉强调 + 双色**
- 现象：`popover-tracks-*` 的当前行同时有：左侧橙色竖条 + 深色圆角均衡器块 + 橙色文字 + 整行底色；dark 下橙色文字对比度仅 3.38:1。
- 证据：`popover-tracks-dark.png`、`popover-tracks-light.png`。
- 改法：保留 1 个主强调（accent 文字）+ 1 个弱背景（`surfaceSelected` 8–12%），删掉左侧竖条与彩色均衡器块（换成 13pt `waveform` 符号、accent 色、无底块）；文字色按 P0-3 clamp。
- 验收：单行内彩色元素 ≤2。

**P1-4 · VIP 徽标引入第二个强调色**
- 现象：`popover-tracks-*.png`、`popover-search-*.png` 的 "VIP" 徽标是粉色填充（视觉观察），与封面暖色、mint 成功色并存。
- 改法：VIP 是状态不是品牌色 → 改成中性胶囊（`surfaceSelected` + `textSecondary` 10pt），或仅在 hover 时展开文字；不要用 rose。
- 验收：全屏彩色像素聚类只允许 1 个非中性色相（封面图除外）。

**P1-5 · 窗口顶部质量胶囊与徽标行信息重复**
- 现象：`window-hero-*.png` 右上角玻璃胶囊写 "无损 | 44.1 kHz · 16 bit · FLAC"，封面下又有一排 `无损 / 44.1kHz·16bit / FLAC / 位完美` 徽标 —— 同一信息出现两次，且胶囊长 ~320pt、压缩了标题栏呼吸感。
- 证据：`window-hero-dark.png`、`window-compact-dark.png`。
- 改法：胶囊只留 "无损 · 44.1 kHz"（≤160pt，图标+2 项），删除封面下的重复徽标行或只留"位完美"1 个；两者取一。
- 验收：同一屏同一条信息只出现一次。

**P1-6 · 设置页头部齿轮按钮冗余 / 危险动作过重**
- 现象：`settings-popover-*`、`popover-settings-*` 页头有返回 + 齿轮；齿轮在当前页无意义。`settings-full-*` 里"退出净听"是通栏 rose 胶囊，"退出/退出登录" 又是 2 个 rose 胶囊 —— 一屏 3 个危险按钮 + 4 行"关于"说明。
- 证据：`settings-popover-dark.png`、`settings-full-dark.png`、`settings-full-light.png`。
- 改法：设置页头部改为 返回 + "完成"（或只留返回）；"关于"压到 ≤2 行 12pt；"退出净听"降级为普通行（rose 文字、无通栏底），B 站/网易云退出保留小号 bordered；一屏 ≤2 个 rose 元素。
- 验收：设置页 rose 胶囊 ≤2；说明文字 ≤2 行。

**P1-7 · 登录页文案与装饰堆叠**
- 现象：登录页有 品牌标记+脉冲环、副标题、二维码（约 230pt 高，带投影）、状态行、"登录后可…"长句、`© BIT-PERFECT OUTPUT` 全大写微标签；空余留白 300pt+。QR 卡片白色 100% 不透明在深色下像一块灯箱。
- 证据：`popover-login-dark.png`、`popover-login-logging-in-dark.png`（注：该组尺寸问题见 P0-2）。
- 改法：QR 卡片白底保留（扫码需要），但尺寸回到 **176–190pt**、取消投影/描边；文案减到 2 条（1 条状态 + 1 条 11pt 说明）；删除全大写版权行（或改 sentence case 9pt tertiary）；顶部品牌标记与脉冲环保留 1 个即可。
- 验收：登录页文字块 ≤3 个层级、QR ≤190pt。

### P2 — 打磨项

**P2-1 · 搜索框尾部两个圆形按钮 + 彩色描边**
- 现象：`popover-search-*` 搜索框右端同时有 清空 ✕ 与 橙色实心 → 提交按钮；框体用 accent 描边。macOS 搜索框通常只有清空，Return 提交。
- 改法：删除橙色提交按钮（保留 Return 键提交）；清空按钮跟随系统 `xmark.circle.fill` tertiary；描边改 `DS.Palette.hairline`，focus 时用系统 focus ring。
- 验收：搜索框内右侧控件 ≤1。

**P2-2 · 空状态图标与按钮风格不统一**
- 现象：`popover-bili-*` 空状态是"圆形 tint 底 + 圆角矩形 play 符号"（方圆混用），下方 3 行说明文字，主按钮是白/黑反转大胶囊（不是 accent 玻璃）。
- 改法：单符号 `play.circle`（28pt，hierarchical，accent），说明 1 行 11pt；主按钮用 `.glassProminent`（tint=albumTint）或 `.borderedProminent` 24–28pt 高。
- 验收：空状态 ≤1 图标 + 1 标题 + 1 说明 + ≤2 按钮。

**P2-3 · 全大写微标签过多**
- 现象：侧边栏 `PURELISTEN`、登录 `© BIT-PERFECT OUTPUT`、设置页脚 `© BIT-PERFECT · 本地播放 · 无广告` 均为全大写 + 字距；brief 明确 macOS 26/27 已改用 title case（不再全大写）。
- 改法：品牌名保留"净听"中文 + 可选 lowercase "purelisten" 9pt 无字距；页脚改 sentence case，或直接删除。
- 验收：界面中无全大写英文微标签。

**P2-4 · 迷你播放台底部左右圆角外侧漏出列表行**
- 现象：`popover-home-dark.png`/`popover-tracks-*` 底部，玻璃台左右内缩约 10pt、底部几乎贴边（2pt），列表行从底部两个圆角外侧露出（"27 首"、"Bill Evans" 被裁断），像渲染错误。
- 改法：① 四周统一内缩 12–16pt（含底部），并给列表加 `safeAreaInset(edge: .bottom)`；或 ② 玻璃台全宽贴底 + 内容底部加 `.scrollEdgeEffectStyle(.soft, for: .bottom)` 渐隐；③ 播放台左右留白处用同色底或 mask 盖住。
- 验收：播放台四周 10pt 区域内不出现任何内容像素。

**P2-5 · 预览/测试场景污染评审基线**
- 现象：`gallery-*` 仍使用系统蓝进度条、5 色彩色徽标（粉/紫/黄/绿/红）与黑/白反色播放键；`marktest-*` 中 48pt 标记用系统蓝、`TileMark` 使用文字"净"（违反"图标不写字"）。这些是 Debug 场景，但会被截图评审误读为产品界面。
- 改法：gallery/marktest 也接入 `albumTint` 与 DS 令牌；删除 TileMark 或移出 catalog；catalog 里加注释说明哪些是实验室场景。
- 验收：全部 50 张截图扫描不到系统蓝 chrome 像素。

---

## 3. 最低 Golden Gate 达标清单（9 条，window-dev / settings-dev 自检用）

1. **单一强调色**：全屏只有 albumTint 一种彩色；chrome 内不出现 `#007AFF/#0A84FF` 家族（用附录 A 脚本扫描，目标 0 px）。
2. **玻璃只在 chrome 层**：玻璃只用于浮动控制/HUD（播放台、质量胶囊、分段胶囊）；卡片、列表、设置行一律实体表面。
3. **对比度**：正文与次级说明（≥11pt）≥ 4.5:1；10pt 仅元数据；浅色模式与深色模式都要过（当前浅色次级 2.29–4.28）。
4. **几何**：窗口 16pt / popover 20pt / 卡片 12pt / 行 10pt；嵌套同心 `r = outer − inset`；不自己画窗口圆角。
5. **控制高度**：只用 20/24/28/36pt 四档；主播放 36pt；点击区 ≥44pt。
6. **字体**：只用系统 ramp（26/22/17/15/13/12/11/10），时间码 `.monospacedDigit()`；无自定义字号；无全大写英文微标签。
7. **洗色**：封面氛围色峰值 ≤35%；浅色底不得变成米色（画布底部色差 ≤2%）；内容区保持中性。
8. **动效**：交互 `.interactiveSpring()`（≈0.15s）；结构 `.snappy`/`.smooth`；无 `.linear`、无循环闪烁（播放指示除外）。
9. **图标**：SF Symbols + hierarchical；13–17pt；菜单栏 17pt template、1.5px 线宽；界面图标不写字（含 TileMark）。

---

## 4. 事实 / 推测 分界

**事实（用像素/数值验证过）：**
- popover 面板 372×588（22 个正常场景）与登录场景 895pt；窗口 940×640；settings-full 372×1240（规格页，非缺陷）。
- 开关 #3C7FF4 与各截图蓝像素计数（附录 A）。
- 对比度 4 处不合格的具体数值；洗色起止色；播放台高度 ≈120pt；重复信息/冗余按钮/漏行现象均为截图可见。
- `login-*` 场景面板比 `popover-login-*` 高 307pt 且顶部透出桌面 —— 这是渲染结果。

**推测（需实现同学确认）：**
- 登录 popover 变高：可能是 `NSPopover.contentViewController` 的 `preferredContentSize` 覆盖了 `contentSize`（场景写法与主体路径不同），而非登录页本身在真实 App 里也溢出 —— 用真实 App 点击菜单栏图标验证一次即可定论。
- `window-settings-dark` 与 `window-settings-light` 的开关 ON/OFF 状态不一致（dark 3 个蓝 ON、light 全 OFF）：可能是 `@AppStorage`/预览假数据在两次 scheme 渲染间不同步，也可能是 `.tint` 与外观联动；需要跑一次真实窗口确认哪个是真状态。
- VIP 粉色、mint 成功色是否被定义为"语义色例外"：若产品坚持保留，请把语义色限定在 success/warning/danger 三类且每屏 ≤1 处，并写进 DESIGN.md。
- `login-*` 顶部灰块右侧的模糊画面：判断为更高 popover 窗口的玻璃背景透出桌面，但未逐层验证。

---

## 5. 附录 A · 关键测量数据与方法

**面板尺寸**（RGBA alpha>250 包围盒 ÷2）：popover 正常 372.0×587.5pt；登录场景 372.0×895.0pt；窗口 940.0×640.0pt；settings-full 372.0×1240.0pt。

**关键色值（截图采样，sRGB）：**

| 元素 | 深色 | 浅色 |
|---|---|---|
| 画布顶部（popover-home） | `#412F28` | `#F3EFEC` |
| 画布底部 | `#151012` | `#D2CDC8` |
| 播放暂停圆盘 | `#F2F2F2` | `#1F1F1E` |
| 设置开关 ON | `#3C7FF4`（系统蓝） | `#3B7FF3` 同族 |
| HUD 胶囊填充（window hero） | `#45371F` | `#D9D4CC` |
| 歌曲副标题文字/底 | `#AAA5A3` / `#2A1D18` | `#68625F` / `#DACCC2` |
| 头部副标题文字/底 | `#7F7570` / `#2E1E19` | `#8B807A` / `#D5C5BB` |
| 正在播放行文字/底 | `#9E6140` / `#291C17` | `#5C3723` / `#D3C8BF` |

**对比度（WCAG，取文字核心 5% 与背景 95% 分位）：** 头部副标题 2.29:1(light)/3.56:1(dark)；艺人副标题 3.84:1(light)/6.87:1(dark)；设置行说明 4.28:1(light)/6.23:1(dark)；播放行强调 3.38:1(dark)/6.31:1(light)。

**系统蓝检测脚本（可复现）：**
```python
from PIL import Image; import numpy as np
a=np.array(Image.open(path).convert('RGB')).astype(int)
r,g,b=a[:,:,0],a[:,:,1],a[:,:,2]
blue=(b>200)&(g>90)&(g<210)&(r<120)&((b-r)>110)
print(blue.sum())   # chrome 目标: 0
```

**截图复现：**
```bash
cd /Users/halo/dsharness/PureListen
swift build -c debug --product PureListen          # 本评审用独立 scratch path，避免与他人 .build 冲突
caffeinate -u -t 2
.build/debug/PureListen --ui-studio --out docs/design/screens
# 本评审快照: docs/design/screens/review-1/*.png  (50 张)
```

**快照文件索引：** popover：`popover-home / popover-tracks / popover-search / popover-settings / popover-bili / popover-login / popover-login-scanned`；设置：`settings-popover / settings-popover-bili / settings-popover-permission / settings-window / settings-full`；登录：`popover-login / login-waiting / login-scanned / login-failed / login-logging-in`；窗口：`window-hero / window-lyrics / window-signal / window-settings / window-idle / window-compact`；其它：`bili-web-login / gallery / marktest`。每场景含 `-dark.png` / `-light.png`。

---

*REVIEW-1 完成。修复优先级：P0-1（蓝开关）→ P0-3（对比度）→ P1-1（洗色）→ P0-2（登录溢出，先确认根因）→ 其余按序。改完请重跑 `--ui-studio` 并保留一份新的 `review-2/` 快照，便于逐条 diff。*
