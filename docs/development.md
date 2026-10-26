# 开发接管与首轮改进

日期：2026-10-26（Asia/Shanghai）。本地目录 `/Users/halo/zcode/purelisten`。

## 基线与结构

接管时本地 `main` 在 `56b1401`，工作区干净；远程已有两次界面更新，已快进同步到 `dbe8a2e`，随后建立 `codex/playback-network-reliability` 分支。保留远程的 Liquid Glass 设计、图标与研究资料。

- `PureListen/App.swift`、`PureListenApp.swift`：AppKit 菜单栏入口、面板与窗口生命周期。
- `PureListen/AppState.swift`：登录、歌单、快捷来源、下载任务、播放队列与偏好。
- `PureListen/Views`、`Design`：SwiftUI 页面和共用设计组件。
- `PureListenCore/NCAPI`：网易 weapi/eapi、B站登录与收藏、来源解析、网络传输。
- `PureListenCore/Audio`：完整文件缓存、CoreAudio 独占输出、ExtAudioFile 解码及环形缓冲。
- `UIPreview`：使用隔离数据渲染真实窗口，供无音频界面验证。

当前工程最低 macOS 26；本轮使用 Swift 6.4 / Xcode macOS 27 SDK 验证。

## 本轮改进

### 网络与登录

新增共用 `NetworkMode` 与 `CurlTransport`。国内服务默认直接连接，API 与下载均忽略应用层系统代理及终端代理环境变量。只有用户手动选择「跟随系统代理」才读取系统 HTTP(S)/SOCKS 或终端代理；下载会话与 API 使用同一模式。API 的 PAC 自动代理暂不支持，会返回说明性错误。

curl 失败退出、HTTP 错误和超时不再伪装成空 JSON；取消任务会终止对应进程。短链展开复用同一传输层，不再同步等待进程阻塞调用线程。临时请求文件放在权限 `0700` 的独立目录并在完成或失败后清理。

修复网易云和 B站通用 API 的响应头分行：Swift `String.split(separator: "\n")` 无法按预期拆开 CRLF 字符簇，导致 `Set-Cookie` 漏读；现在使用 Foundation 的换行分隔，保留 Version=1 以及值中带等号的 Cookie。网易 Cookie 读取增加互斥保护，日志移除生产路径的完整登录响应头与 B站跨域票据地址。

### 下载与缓存

改用 `URLSession.download(for:delegate:)` 将文件下载到磁盘，并报告真实传输进度。缓存名称包含完整 URL、调用方 key、请求头与格式的 SHA-256 标识，避免不同站点或账号的同名音源串用。签名 URL 更新会建立另一份缓存。

只有 HTTP 200、大小合理且不是 HTML/JSON/XML 错误页的响应才提交为缓存。提交失败会抛出错误；并发下载同一资源时可以复用另一请求已提交的完整文件。旧版缓存保留，仍可通过设置页清除。

### 播放与输入

播放解析、下载及歌词请求记录请求身份；切歌、取消等待、登出或退出应用会取消旧任务。即使旧请求忽略取消并延迟返回，也不能改写新播放。开始新请求前停止旧播放，避免界面显示下载而旧曲仍在输出。

B站的上下曲及自然播完现在沿当前分 P 队列移动，结束时释放播放。单独传入的条目自动建立单项队列。手动换设备时保留 B站/直链来源，先停止旧设备再更换目标 ID。

修复 BV/av 正则提取，支持分享文案中的链接、网易 `/#/song?id=` 与 B站 `?p=`。站点匹配使用真实 hostname，音频格式取 URL 路径扩展名，避免查询参数导致误识别。

保存静音音量 0、关闭的系统音量镜像与音质偏好。修复预览模式间接枚举设备、触发镜像或媒体键逻辑的问题。

### 构建与诊断

`build.sh` 从 SwiftPM 查询实际二进制目录，先在临时目录组装并验证签名与 plist，再更新 `dist/净听.app`。按用户后续要求，默认备份旧版并保留数据安装到 `/Applications/净听.app`；保留现有稳定签名身份的选择逻辑。截图脚本也不再假定 `.build/debug` 路径。

新增 `apitest resolve <链接/BV/ID>`，只解析来源，不下载或播放。命令异常现在以非零退出码结束。

## 验证

- `swift test`：23 项通过（核心 18、应用状态 5）。
- `./build.sh`：Release 构建、`PureListen Dev` 签名、严格签名验证和 plist 检查通过。
- 本地 HTTP 服务覆盖下载缓存命中、同名隔离、并发提交、错误页、占位内容、提交失败、取消、超时、重定向、Version=1 Cookie。
- 应用状态测试故意让 A → B → A 的旧请求乱序结束，确认最新请求保留；另覆盖取消等待、分 P 上下曲和换设备时保留来源。测试使用隔离偏好及下载依赖，不启动音频设备。
- 初轮验证过可选的系统代理路径；随后根据用户澄清，将国内服务改为默认直连。保留的回归测试验证默认直连会覆盖代理环境变量，系统代理只在手动选择时生效；保留终端代理环境变量运行 `apitest hct`，直连路径返回 HTTP 200 / code 0。
- `apitest resolve 'https://www.bilibili.com/video/BV1xx411c7mD/?p=1'`：返回 1 项 m4a / 132kbps DASH 音频；只解析，无声音。
- 设置页深色、浅色截图均已生成并检查，网络选项与说明可以正常显示。

构建产物在 `dist/净听.app`；本地日志、截图和校验值存放在 `dist/verification/`，该目录不入 Git。

## 后续优先核查

1. **音频格式与资源生命周期**：引擎的环形缓冲和安全钳制按 Float32 处理，但设备物理格式可能是整数或非交错布局；位完美标记目前也主要依据音量。下一轮需明确受支持的 PCM 格式，并用真实输出抓取对比和多设备测试验证。
2. **热插拔与暂停语义**：现有热插拔重启路径会把暂停曲目也视作可续播对象；还需核查设备 ID 回收、解码线程退出超时和 seek 与 IO 的并发访问。
3. **长歌单与过期链接**：歌单接口返回的曲目列表可能不覆盖完整长歌单，B站长分 P 列表则会提前获取多个有时效的音频链接。可后续改为按需解析和分页加载。

本轮未运行会出声的 `hogtest`，未实测耳机热插拔、外置 DAC 或位完美输出，也未进行账号扫码登录。网络与状态回归通过不能替代这些真实设备与账号验证。

## 网络实现参考

- [Apple：URLSession 的系统代理与下载接口](https://developer.apple.com/documentation/foundation/urlsession)
- [Apple：connectionProxyDictionary 默认使用系统设置](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/connectionproxydictionary)
- [Apple：系统 HTTP 代理开关](https://developer.apple.com/documentation/cfnetwork/kcfnetworkproxieshttpenable)

## 后续修复：播放栏外的黑影

用户反馈浅色模式下，浮动播放栏外有大块黑色阴影。处理了两个来源：关闭播放栏额外叠加的黑色投影并按圆角裁切玻璃效果；将外观环境传递给背景和内容，使浅色的 AlbumWash 不再误用默认深色底部遮罩。

同时修正预览锚点重复挂载 SwiftUI 内容的问题，避免截图在透明窗口后面再渲染一份界面。已逐轮查看歌单页浅色、深色的真实 NSPopover 截图，并检查设置页；产物与截图记录在 `dist/verification/transport-shadow/`。本次为视觉修复，采用 Debug/Release 构建和截图核对验证，没有新增或重复运行音频测试。

## 后续约定：每次新版自动保留数据安装

根据用户要求，已将默认 `./build.sh` 流程改为构建、签名验证后安装到 `/Applications/净听.app`，并写入根目录 `AGENTS.md`。用户明确要求只检查构建时，可用 `PURELISTEN_NO_INSTALL=1` 跳过安装。

`tools/install-app.sh` 先验证并暂存新应用，正在运行时正常退出，随后移动旧包、替换并再次验证；失败时恢复旧包。旧应用和偏好备份保存在权限 0700 的 `~/Library/Application Support/PureListen Upgrades/`。该流程只替换应用包，不移除或重建偏好、登录资料、WebKit 数据和歌曲缓存；原本运行时安装后重新打开，原本未运行时保持关闭。

本次已实际安装当前修复版，确认安装包与构建产物的二进制、plist 相同，旧包签名验证通过，新旧签名要求一致。升级前后对偏好、CLI 登录资料及现有缓存、HTTP 存储合计 124 个文件做 SHA-256 比对，全部未变。还验证了签名损坏的新包会在替换前被拒绝，原安装保持不变。验证记录在 `dist/verification/install-upgrade/`。
