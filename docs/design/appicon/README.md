# 净听 PureListen — macOS 27 "Golden Gate" 应用图标 & 菜单栏模板图标

> 目录：`docs/design/appicon/` · 生成脚本：`make_icon.swift`（纯 Swift + CoreGraphics，无第三方依赖）
> 设计基准：`docs/research/macos27-design-language.md` §3.7 / §3.1 / §3.5（HIG + macOS 27 实测）

## 1. 产出文件

| 文件 | 规格 | 用途 |
|---|---|---|
| `icon_1024.png` | 1024×1024 RGBA，透明外缘 | 主图（Apple 824 网格 + 内建投影） |
| `AppIcon.icns` | 16/32/128/256/512 @1x@2x | 打包用（`build.sh` 已支持 `Resources/AppIcon.icns`） |
| `icon_16.png` / `icon_32.png` | 16/32 px | 小尺寸自检样张（光学补偿变体） |
| `menubar_template.png` | 17×17 px 单色 + alpha | 菜单栏 template（`isTemplate = true`） |
| `menubar_template@2x.png` | 34×34 px | Retina 菜单栏 |
| `menubar_visibility_check.png` | 900×360 | 浅色 / 深色 / 半透明壁纸三种菜单栏底色下的可见性验证（6× 放大） |
| `icon_preview.png` | 1200×720 | 亮/暗背景 + 128/64/32/16px 尺寸阶梯评审预览 |
| `make_icon.swift` | — | 可复现生成脚本 |
| `README.md` | — | 本文件 |

## 2. 设计说明

### 2.1 造型：把品牌标记演绎成"一张唱片"

品牌标记（`Sources/PureListen/Design/Components.swift` 的 `DSBrandMark`）是 **开口圆环 + 中心点**，意象为唱针落点。图标把它推进一层：

- **深色唱片盘**（半径 292，近黑靛蓝渐变 + 3 道极浅纹圈 + 微弱"标签"圆盘）→ 让符号一眼读成唱片，而不是"C / 加载圈"；
- **唱片环**：环半径 258、环宽 58、**18° 开口**（开口中心 -55°，即右上 1–2 点钟方向），平切口（`butt` cap），白色玻璃渐变；
- **中心点**：半径 56，下方 1.62× 处一圈 0.16 alpha 细线，暗示唱片标签边缘；
- **18° 开口是品牌识别点**：大尺寸保留精确 18°；≤32px 开口放大到 14° 以保形；≤16px **闭合开口**（16px 下人眼无法分辨 1.5px 的缺口，闭合反而更干净、更像唱片）。

> ⚠️ 事实校正（供实现参考）：`DSBrandMark` 当前 `addArc(startAngle: 196°, endAngle: 506°)` 扫过 310°，**实际开口是 50°**，与注释写的 18° 不符。图标按"18–20° 开口"的品牌意图绘制；建议把 UI 来源对齐到 18–20°（见 `docs/design/REVIEW-1.md`）。

### 2.2 分层液态玻璃（Golden Gate 的"玻璃方块"）

图标是静态资产，`glassEffect` 无法在 `.icns` 里生效，因此按 macOS 27 玻璃的**光学结构**手工复刻为 5 层：

1. **玻璃底**：超椭圆（superellipse n≈5）圆角方块，824×824 @ 1024 画布（Apple 图标网格），等效圆角 185.4；渐变 `#6E57F5 → #3A28A8 → #120B33`（深靛蓝→紫罗兰→近黑），右上角 `#5BE9DA` 青绿冷光（0.34 alpha）、左上 `#A895FF` 柔光、底部 0.40 压暗、−32° 斜向反光带；
2. **内层玻璃片**：内缩 58 的超椭圆，上亮下暗（白 0.15 → 0.004）+ 底部内阴影；
3. **边缘**：内侧 3px 镜面描边（白 0.34→0.02）+ 外侧 1.4px 暗线，保证在浅色桌面/白色背景上也有轮廓；
4. **内片高光边**：1px 渐变描边（白 0.62 → 黑 0.22），模拟玻璃厚度；
5. **符号**：玻璃渐变（`#FFFFFF → #D3CAFF`）+ 顶部高光弧 + 下方柔和投影；环下半段有一道极淡的深色折射边（只画在下半圆内，避免切口处出现碎块）。

**不做的**：拟物噪点/纹理、文字、系统蓝（`#007AFF`/`#0A84FF` 均未使用）、高饱和彩虹色、堆叠多层玻璃。

### 2.3 光学尺寸（16/32px 自检）

| 尺寸 | 处理 |
|---|---|
| 1024–64 | 原设计；内片/纹圈/高光弧全部保留 |
| ≤32 | 符号放大 1.10×、环宽 ×1.28、中心点 ×1.16、开口缩到 14°；去掉纹圈/标签圆盘/高光弧（缩到 32px 只会变成噪点） |
| ≤16 | 开口闭合、符号放大 1.05×、环宽 ×1.30、中心点 ×1.16；内片与描边加粗；8× 超采样后降采样，避免 1px 锯齿 |

`icon_preview.png` 右下是 16px 原尺寸阶梯，`icon_16.png`/`icon_32.png` 可直接用图片查看器按 800% 放大自检。

## 3. 如何重新生成

```bash
cd /Users/halo/dsharness/PureListen
swift docs/design/appicon/make_icon.swift
```

- 需要 macOS + Xcode Command Line Tools（脚本用 AppKit / CoreGraphics / CoreText / ImageIO）。
- 脚本只会写 `docs/design/appicon/`（中间 `AppIcon.iconset` 生成后自动删除），不改 App 源码。
- 输出确定性：同一脚本多次运行，PNG 字节级一致（无时间戳/随机数）。

**想调参**：脚本顶部 `palette` / `symbol` 两个常量集中了配色与符号几何（环半径、环宽、开口角度、唱片盘半径、纹圈数），改完重跑即可。

## 4. 接入 `build.sh`（零改动路径）

`build.sh` 已经预留了图标钩子，**不需要修改 build.sh**：

```bash
# build.sh 现有逻辑：
#   if [ -f "Resources/AppIcon.icns" ]; then cp .../AppIcon.icns "$APP/Contents/Resources/"; fi
#   Info.plist 中 CFBundleIconFile = AppIcon
mkdir -p Resources
cp docs/design/appicon/AppIcon.icns Resources/AppIcon.icns
./build.sh          # 产出 dist/净听.app，图标即生效
```

> `build.sh` 里有一行注释写着 "由 tools/make_icon.swift 生成"；本目录的规范路径是 `docs/design/appicon/make_icon.swift`。按约束我未改 build.sh，建议 Lead/实现同学顺手把注释改成实际路径，或建一个 `tools/make_icon.swift` 软链接。

**为什么是 `.icns` 而不是 Icon Composer 的 `.icon`**：SwiftPM + 手写 bundle 的构建链路只认 `CFBundleIconFile`（`.icns`）。macOS 26/27 的 layered/clear/tinted 图标外观需要 Xcode asset catalog + Icon Composer 的 `.icon` 资产；当前链路下 `.icns` 是务实选择（Finder/Dock/启动台都能正常显示）。若将来迁移到 Xcode 工程，再补 `AppIcon.appiconset`（1024 单尺寸 + 自动生成变体）即可，本脚本的输出可直接当 1024 源图。

## 5. 菜单栏 template 图标

| 项 | 规格 |
|---|---|
| 画布 | **17×17 pt**（@1x 17px / @2x 34px），菜单栏高度实测 **33pt**（brief §3.2） |
| 几何 | 环半径 **5.36pt**（17×0.315），环宽 **1.5px**（1x），中心点直径 **2.6pt**，开口 **42°**（右上） |
| 颜色 | 纯黑 + alpha（`isTemplate = true` 交给系统着色） |
| 文件 | `menubar_template.png`（17×17）、`menubar_template@2x.png`（34×34） |

**为什么菜单栏开口用 42° 而不是 18°**：17pt 画布上 18° 开口的弧长只有 1.7pt，1.5px 圆头线帽会把缺口吃掉，缩到菜单栏后看不出"开口唱片"。42° 开口的弧长约 3.9pt，在 1x 下仍有约 3px 缺口，且不像 18° 那样容易被误读成"C"。这是**尺寸补偿**，不是品牌变更：图标（大尺寸）保持 18°，菜单栏标记保留"开口环 + 点"的识别特征。

**可见性判断（实测 + 验证图）**：

- 本机菜单栏是**半透明**的：对菜单栏截图实测背景亮度（WCAG 相对亮度）在 **L≈0.17–0.28** 区间（空区 L≈0.167，状态区 L≈0.235，标题区 L≈0.276；采样自 `docs/research/refs/01-menubar-macos27.png`）。
- template 图像由系统按菜单栏外观自动着色：**浅色菜单栏画黑、深色/壁纸透出时画白**，并带轻微 vibrancy/阴影。所以设计只需保证**剪影清晰**：环宽 1.5px、开口 42°、中心点 2.6pt 在该亮度区间内都成立（`menubar_visibility_check.png` 用黑/白两种着色 × 浅色/深色/壁纸三种底色验证）。
- 需要避免的坑：① 线宽 <1.2px 在 1x 会断线（本设计固定 1.5px）；② 不要给 template 加彩色（会被系统忽略或产生脏边）；③ 不要用空心细环 + 小点（16pt 菜单栏里最容易糊成"@"）。
- 若希望**更"Golden Gate"**：菜单栏标记可保留"播放时环略粗/点呼吸"的状态差异（当前 `App.swift` 的声波图标靠弧度表达播放态），但差异应 ≤1px，避免菜单栏图标跳动。

### 与当前 `App.swift` 的差异（仅说明，未改代码）

`App.swift` 的 `StatusItemIcon` 目前在画 **中心点 + 左右声波弧**（18×18pt，template），与 `DSBrandMark` 的"开口唱片环"不是同一个符号；品牌一致性上建议统一为唱片环几何（脚本里的数值可直接照搬：环半径 5.36pt、环宽 1.5px、开口 42°、中心点 2.6pt）。接入方式二选一：

```swift
// A. 从 bundle 加载 @1x/@2x template（需把两个 PNG 拷进 Resources/）
let image = NSImage(size: NSSize(width: 17, height: 17))
image.addRepresentation(NSBitmapImageRep(data: Data(contentsOf: url1x))!)
image.addRepresentation(NSBitmapImageRep(data: Data(contentsOf: url2x))!)  // 34×34
image.isTemplate = true
statusItem.button?.image = image

// B. 继续用代码画（推荐，零资源依赖）：按上面几何用 NSBezierPath 画环+点，isTemplate = true
```

## 6. 已知限制 / 后续

- `.icns` 是**单图层静态资产**，不能随 macOS 27 的图标外观（default/dark/clear/tinted）自动变化；需要时再迁 Icon Composer（见 §4）。
- 图标阴影是**烘焙**在透明画布内的（macOS 应用图标约定）；不要在 bundle 里再叠系统阴影。
- 16px 版本做了"闭合开口"的简化：这是有意的光学补偿，与 UI 内 22pt+ 的品牌标记不 100% 同形（Apple 自己也会为小尺寸简化细节）。
- 若后续品牌标记的开口角度在 UI 中改为 18–20°，本脚本 `symbol.gap = 18` 保持同步即可。
