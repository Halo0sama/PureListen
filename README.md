# 净听 PureListen

**网易云音乐 · 哔哩哔哩 · macOS 独占音频输出**

一款 macOS 菜单栏音乐播放器，支持网易云歌单、哔哩哔哩收藏夹与音频直链。播放器根据音源切换设备采样率，使用 Core Audio 独占输出，并支持边播放边缓存。

<p align="center">
  <img src="docs/design/gallery/popover-home.jpg" width="330" alt="菜单栏面板" />
  <img src="docs/design/gallery/window-hero.jpg" width="560" alt="正在播放窗口" />
</p>

> **v2.1.0**：边播放边缓存、四种播放模式、独立播放队列、DAC 重连保护与竖向音量条。下载见 [Releases](https://github.com/Halo0sama/PureListen/releases/latest)，完整变更见 [CHANGELOG.md](CHANGELOG.md)。
> Liquid Glass 界面设计与实现说明见 [docs/design/README.md](docs/design/README.md)。

## 它解决什么问题

系统共享输出的采样率可能与音源不同。净听提供独占设备、自动切换采样率和播放链路信息，方便确认当前音源及设备状态。

播放链路：

1. **hog mode 独占输出设备**：播放期间由净听接管所选输出，暂停或停止时释放。
2. **自动切换采样率**：读取音源格式并请求设备使用相同采样率；实际能力取决于设备。
3. **PCM 输出**：解码后的 Float32 PCM 经过环形缓冲送入 HAL 回调，避免在实时回调中下载或等待。
4. **状态可见**：显示音源质量、采样率、位深、缓存、设备与音量衰减。界面的位完美标记是软件状态判断，不是对 DAC 输出的逐位测量；低于 100% 的软件音量会执行数字衰减。

## 界面

| 菜单栏面板 | 正在播放窗口 |
|---|---|
| 顶栏 · 分段浏览 · 浮动玻璃播放台 | edge-to-edge 侧边栏 · 大封面 · 歌词 · 播放链路 |

- **菜单栏面板** (372×588)：网易云 / 哔哩哔哩分段浏览，搜索、设置与音量位于顶栏；底部浮动播放台显示当前歌曲、进度和播放模式。
- **「正在播放」窗口** (940×640)：封面模糊铺满背景，左侧 edge-to-edge 侧边栏，四个页面：正在播放 / 歌词 / 播放链路 / 设置。点面板右上角或右键菜单即可打开。
- **歌词页**：当前行放大加粗、译文紧随，点击任意行跳转。
- **播放链路页**：音源 → 解码 → 缓冲 → 独占输出 → 设备的实时状态与格式信息。
- **设置页**：音质、输出设备、播放保护、B站账号、缓存、账号与退出；面板与窗口共用同一套卡片。
- **登录页**：扫码登录，二维码卡片、已确认状态、失败重试。
- **菜单栏图标**：自绘 template 图标（唱片环 + 中心点），播放时环线加粗；左键开面板，右键出原生菜单。

所有界面颜色只来自当前封面的「音乐色」+ 黑白灰；支持浅色/深色、降低透明度、减少动态效果。**界面不读取任何音频电平**，也不参与音频链路的处理。

其余截图见 [`docs/design/gallery/`](docs/design/gallery)。

## 功能

- **网易云独占播放**：扫码登录、歌单、无损 / Hi-Res 取链、选择输出设备、自动采样率切换
- **播放队列与模式**：顺序、列表循环、单曲循环和随机播放；浏览其他歌单不改变正在播放的封面和队列，随机模式的上一首沿历史回退。
- **边播放边缓存**：网易云 FLAC、B 站 AAC / Hi-Res 可在整首下载完成前开始解码；拖动时按需获取片段，进度条显示已缓存部分。
- **哔哩哔哩播放**: 支持视频链接/BV号/b23短链、分 P 与带封面的收藏夹；可选 Hi-Res FLAC、高音质、标准或省流，按音源与账号权限回退。默认高音质，偏好独立于网易云。
- **直链播放**: 粘贴任意音频直链(FLAC/MP3/M4A/WAV…)
- **链路可视化**：进入正在播放页的「链路」分栏，查看音源、解码、缓冲、独占输出、设备、采样率、位深和音量衰减
- **音量键接管**: 独占时系统音量键本已无效, 开启接管后(需辅助功能权限)由本 App 响应
- **系统音量联动**：同步所选设备的硬件音量变化；音量键接管需要辅助功能授权
- 默认 10% 安全音量；切换或重连输出后降至最多 10%，保留静音和更低音量
- **设备插拔**: 立即停止旧输出，保留曲目/进度，连接稳定后由用户点击播放；手动锁定的解码器断开后保留选择，不自动转到扬声器

## 系统要求

- **macOS 26.0 或更高**
- Apple Silicon 或 Intel Mac

## 使用

从 [Releases](https://github.com/Halo0sama/PureListen/releases/latest) 下载通用 ZIP，解压后将 `净听.app` 放入 `/Applications`。升级时先退出应用，再替换旧应用包；不要删除用户资料目录。发布包使用项目开发证书签名，尚未经过 Apple 公证。

从源码构建（需要 Xcode 26 或更高版本）：

```bash
./build.sh          # 构建 arm64 + x86_64 通用包，签名并保留数据安装
# 只构建本机架构：PURELISTEN_ARCHS="$(uname -m)" ./build.sh
# 仅检查构建、不安装时：PURELISTEN_NO_INSTALL=1 ./build.sh
```

每次新版默认自动安装。升级只替换应用包，保留账号、设置、网页登录资料和歌曲缓存；旧版及偏好备份位于 `~/Library/Application Support/PureListen Upgrades/`。正在运行时先正常退出，升级验证成功后重新打开；未运行时保持关闭。安装失败会恢复旧版。

1. 菜单栏出现唱片环图标, 点开扫码登录 (用网易云音乐 App 扫);
2. 选择输出设备、歌单和歌曲；首次播放音量默认为 10%；
3. 可在设置里调整启动播放、音质与设备偏好。设备重连会暂停，需手动点击播放。

## 界面预览 / 开发

界面可以在**完全不发声**的情况下单独预览与截图（Debug 专用）：

```bash
swift build -c debug --product PureListen
BIN="$(swift build -c debug --show-bin-path)"
caffeinate -u -t 2
"$BIN/PureListen" --ui-studio --out docs/design/screens                 # 全部场景, dark + light
"$BIN/PureListen" --ui-studio --out /tmp/shots --only window            # 只看主窗口
```

`--ui-studio` 用假 `AppState`（不枚举音频设备、不联网、不启轮询）把真实的 `NSPopover` / `NSWindow` 渲染出来再抓图，因此整个设计验证过程不会发出任何声音。也可以直接运行 `tools/shoot-screens.sh` 一键重出全部截图。

## 网络与 VPN

网易云、B站 API 与音频下载默认「直接连接」，忽略系统应用层代理和 `http_proxy` / `https_proxy` / `all_proxy` 等终端代理环境变量。开发环境启用 VPN 不会使应用自动启用代理；TUN 模式的路由仍由 VPN 本身控制。

仅在手动选择「跟随系统代理」时，API 才读取系统 HTTP(S)/SOCKS 代理或终端代理环境变量，下载会话才使用系统代理。切换对新请求生效，可重新点播；API 暂不支持 PAC 自动代理。

缓存文件使用完整 URL 与请求头的 SHA-256 标识，防止同名音源串用。旧缓存保留，首次播放会建立新版缓存；签名 URL 改变也会产生新缓存，可在设置中清理。

## 说明与限制

- **需要黑胶 VIP** 才能取到无损/Hi-Res 直链 (这是网易的版权限制, 与本 App 无关); 非 VIP 自动回退到可用音质。
- 可用采样率、位深与音量控制取决于 Mac 型号和外置 DAC；可在播放链路页检查实际格式。
- 独占播放期间, **其他 App 的声音会被暂时屏蔽** (与 iPhone 接电话时的行为一致), 停止/暂停后恢复。
- 独占模式可使用 App 音量条，或启用音量键接管；低于 100% 的软件音量会执行数字衰减。
- 本 App 使用网易网页端同款 weapi/eapi 接口 (逆向实现), 仅供个人学习研究; 请使用自己的账号, 理论上存在与官方客户端风控策略冲突的风险。
- 歌曲缓存位于 `~/Library/Caches/PureListen`, 可在设置中一键清除。

## 工程结构

```
Sources/
  PureListenCore/            核心库
    NCAPI/                   网易云客户端 (weapi/eapi 加密、扫码登录、歌单、直链)、B站客户端
    Audio/                   独占输出引擎 (hog mode、采样率切换、FLAC 解码、无锁环形缓冲)
  PureListen/                菜单栏 App (SwiftUI)
    Design/                  设计系统: 令牌、组件、封面取色、二维码
    Views/Popover/           菜单栏面板: 根视图、路由、浏览列表、浮动播放台
    Views/Window/            「正在播放」窗口: 外壳、侧边栏、播放页、歌词页、链路页
    Views/Settings/          设置卡片、B站登录卡
    UIPreview/               无音频 UI 预览 / 截图工作室 (Debug only)
  hogtest/                   独占输出链路自测 CLI (生成测试音并验证 hog/切率/恢复)
  apitest/                   API 连通性自测 CLI (二维码创建/轮询、取直链)
Resources/AppIcon.icns       应用图标 (macOS 27 分层玻璃风格)
docs/design/                 视觉规范、设计说明、截图、图标源文件
docs/research/               macOS 27 设计语言研究 + SDK API 速查
tools/shoot-screens.sh       一键重出界面截图
build.sh                     Release 构建 + 组装 .app + 签名验证 + 保留数据安装
tools/install-app.sh         暂存验证、旧版备份、替换失败恢复与安装后校验
```

## 自测

```bash
swift test                                      # 无声音、离线回归测试
swift build                                     # 构建 App 与诊断 CLI
BIN="$(swift build -c debug --show-bin-path)"
"$BIN/apitest" hct                               # B站公开 API 连通性，不登录
"$BIN/apitest" qr                                # 扫码登录链路
"$BIN/apitest" url <歌曲id>                        # eapi 取直链
"$BIN/hogtest" devices                           # 只读设备的虚拟/物理格式
"$BIN/hogtest" verify-muted-gain <设备ID> [--block-others] # 硬件静音保护下验证非零输出和静音恢复
"$BIN/hogtest" verify-silent --generated <设备ID> [第二设备ID]  # 零音量验证；可选双设备切换
"$BIN/hogtest"                                   # 独占链路测试；会出声并临时接管设备
```

回归测试覆盖系统代理策略、HTTP 超时/取消/重定向、并发下载与缓存失败、分享链接识别，以及快速切歌和分 P 队列。使用本机临时 HTTP 服务、独立缓存目录与隔离偏好；不依赖外网、登录账号或真实音频输出。

开发接管记录、验证结果与待处理问题见 [docs/development.md](docs/development.md)。

## 开源

MIT License · 作者 [Halo0sama](https://github.com/Halo0sama)

致谢: [NeriPlayer](https://github.com/cwuom/NeriPlayer)(B站登录与播放页设计参考)、[NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)(接口协议参考)、[bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)(B站接口文档)。

界面设计参考了 Apple Human Interface Guidelines 与 macOS 27 的 Liquid Glass 设计语言；量化研究见 [docs/research](docs/research)。
