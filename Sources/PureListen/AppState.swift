import AppKit
import Foundation
import SwiftUI
import PureListenCore

/// 全局应用状态: 登录、歌单、播放队列、设备与偏好。
@MainActor
final class AppState: ObservableObject {
    enum LoginPhase: Equatable {
        case idle
        case qrWaiting
        case qrScanned
        case loggingIn
        case loggedIn
        case failed(String)
    }

    @Published var loginPhase: LoginPhase = .idle
    @Published var profile: NCProfile?
    @Published var playlists: [NCPlaylist] = []
    @Published var tracks: [NCTrack] = []
    @Published var currentPlaylist: NCPlaylist?
    @Published var currentIndex: Int = -1

    @Published var playerState: ExclusivePlayer.State = .idle
    @Published var trackStatus = ExclusivePlayer.TrackStatus()
    @Published var loadingHint = ""

    @Published var level: NCLevel = .lossless {
        didSet { defaults.set(level.rawValue, forKey: "level") }
    }
    @Published var networkMode: NetworkMode = .direct {
        didSet { defaults.set(networkMode.rawValue, forKey: "networkMode") }
    }
    @Published var volume: Float = 0.1 {
        didSet {
            player.volume = volume
            defaults.set(Double(volume), forKey: "volume")
            // 镜像驱动的更新也会走这里, 但 manualVolumeAt 只在非镜像路径设置(见 setManualVolume)
        }
    }

    /// App 内滑条/媒体键调整音量(与镜像来源区分)。
    func setManualVolume(_ value: Float) {
        manualVolumeAt = Date()
        volume = value
    }
    @Published var autoResume = true {
        didSet { defaults.set(autoResume, forKey: "autoResume") }
    }
    @Published var devices: [AudioDeviceInfo] = []
    @Published var selectedDevice: AudioDeviceInfo?
    /// 快捷播放(B站/直链/网易ID)的当前条目与队列。
    @Published var currentItem: PlayableItem?
    @Published var itemQueue: [PlayableItem] = []
    @Published var quickPlayBusy = false
    @Published var quickPlayError: String?
    // MARK: B站账号
    enum BiliPhase: Equatable {
        case idle, qrWaiting, qrScanned, loggedIn, failed(String)
    }
    @Published var biliPhase: BiliPhase = .idle
    @Published var biliUname: String = ""
    let biliClient: BiliClient
    private var biliPollTask: Task<Void, Never>?
    @Published private(set) var biliQRURL: String?

    // MARK: B站收藏
    @Published var biliMid = 0
    @Published var favFolders: [BiliClient.FavFolder] = []
    @Published var favVideos: [BiliClient.FavVideo] = []
    @Published var currentFavFolder: BiliClient.FavFolder?
    @Published private(set) var favHasMore = false
    private var favPage = 1
    @Published var favBusy = false

    func loadFavFolders() async {
        guard biliClient.isLoggedIn, biliMid != 0 else { return }
        favBusy = true
        defer { favBusy = false }
        favFolders = (try? await biliClient.favoriteFolders(mid: biliMid)) ?? []
        NCLog.log("B站收藏夹加载: \(favFolders.count) 个")
    }

    func openFavFolder(_ folder: BiliClient.FavFolder) async {
        currentFavFolder = folder
        favVideos = []
        favPage = 1
        await loadMoreFavs(reset: true)
    }

    func loadMoreFavs(reset: Bool = false) async {
        guard let folder = currentFavFolder else { return }
        favBusy = true
        defer { favBusy = false }
        if let (videos, more) = try? await biliClient.favoriteVideos(folderId: folder.id, page: favPage) {
            favVideos += videos
            favHasMore = more
            favPage += 1
        }
    }

    /// 播放收藏里的一个视频(自动解析音频)。
    func playBiliVideo(_ video: BiliClient.FavVideo) {
        resolveAndPlay(video.bvid, coverFallback: video.cover)
    }

    // MARK: 搜索
    @Published var searchKeyword = ""
    @Published var searchResults: [NCTrack] = []
    @Published var searchBusy = false

    // MARK: 歌词
    @Published var lyrics: [LyricLine] = []
    @Published var lyricIndex = -1

    /// 播放期间接管其余输出设备(其他 App 全静默; 从根源消除扬声器漏音)。
    @Published var blockOtherOutputs = true {
        didSet {
            defaults.set(blockOtherOutputs, forKey: "blockOtherOutputs")
            player.blockOtherOutputs = blockOtherOutputs
        }
    }

    /// 播放期间系统静音(跟随独占): 独占时其他 App 声音会被甩到扬声器, 静音挡漏音;
    /// 本 App 音乐走独占通道不受系统静音影响。暂停(独占释放)时自动解除。
    @Published var muteSystemWhileRunning = false {
        didSet {
            defaults.set(muteSystemWhileRunning, forKey: "muteSystem")
            applyMutePolicy()
        }
    }
    private var systemMuteSession: SystemOutput.MuteSession?

    private var playbackActive: Bool {
        switch playerState {
        case .playing, .loading: return true
        default: return false
        }
    }

    /// 静音策略: 播放(独占)中→系统静音; 暂停/停止→还原。
    private var permissionPromptShown = false
    /// 初始化期间从 UserDefaults 恢复开关时，不要触发系统授权弹窗。
    private var isRestoringState = true
    /// 回到前台时重新检查辅助功能权限（用户可能刚在系统设置里授权）。
    private var activationObserver: NSObjectProtocol?

    /// 媒体键事件 tap 的启停。
    ///
    /// 注意：这里**不会**主动弹「辅助功能」授权窗。
    /// 净听是 ad-hoc 签名，每次重新构建后系统里旧的辅助功能授权会失配；如果启动就弹窗，
    /// 用户会看到"开关明明是开的却反复弹授权"的骚扰。因此改成只在用户主动打开
    /// 「接管媒体键」开关时请求一次授权，其余时候只在设置页给一条可点击的提示。
    private func updateMediaKeyTap() {
        guard !previewMode else { return }
        let need = playbackActive || mediaControlKeysEnabled
        let permitted = MediaKeyTap.hasPermission()
        mediaKeyTap.isEnabled = need && permitted
        if need && !permitted && !permissionPromptShown {
            permissionPromptShown = true
            NCLog.log("[媒体键] 未获得辅助功能权限, 媒体键接管暂不可用; 可在 设置 → 播放保护 中重新授权")
        }
        // 用户可能正在系统设置里授权：轻量轮询（只查询、不弹窗），授权后立刻启用接管。
        if mediaControlKeysEnabled && !permitted {
            startPermissionPolling()
        } else {
            stopPermissionPolling()
        }
    }

    private var permissionPollTimer: Timer?

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if MediaKeyTap.hasPermission() {
                    self.stopPermissionPolling()
                    self.updateMediaKeyTap()
                }
            }
        }
        if let permissionPollTimer {
            RunLoop.main.add(permissionPollTimer, forMode: .common)
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func applyMutePolicy() {
        guard !previewMode else { return }
        var target = muteSystemWhileRunning && playbackActive ? SystemOutput.defaultOutputIdentity() : nil
        // 已独占的目标没有其他 App 混音，不对音乐本身施加系统硬件静音。
        if target?.id == player.deviceID { target = nil }
        if systemMuteSession?.device != target {
            systemMuteSession?.restore()
            systemMuteSession = nil
            volumeMirror.rebase()
        }
        if let target, systemMuteSession == nil {
            systemMuteSession = SystemOutput.beginMuteSession(on: target)
            volumeMirror.rebase()
        }
    }

    /// 接管 播放/暂停/上一曲/下一曲 媒体键。
    @Published var mediaControlKeysEnabled = false {
        didSet {
            defaults.set(mediaControlKeysEnabled, forKey: "mediaControlKeys")
            // 只有用户主动打开这个开关时才请求辅助功能授权（系统弹窗由用户操作触发）；
            // 从偏好恢复的状态不请求，避免每次启动都弹窗。
            if !previewMode, !isRestoringState, mediaControlKeysEnabled, !MediaKeyTap.hasPermission() {
                MediaKeyTap.requestPermission()
            }
            updateMediaKeyTap()
        }
    }
    let mediaKeyTap = MediaKeyTap()

    /// 打开播放详情窗口(由 AppDelegate 注入)。
    var onOpenNowPlaying: (() -> Void)?
    /// 打开 B 站网页登录窗口(由 AppDelegate 注入)。
    var onOpenBiliWebLogin: (() -> Void)?

    /// WebView 登录完成, 收割 Cookie。
    func finishBiliWebLogin(webCookies: [String: String]) {
        guard webCookies["SESSDATA"]?.isEmpty == false else { return }
        biliClient.applyWebLoginCookies(webCookies)
        defaults.set(biliClient.cookies, forKey: "biliCookies")
        if let dede = webCookies["DedeUserID"], let mid = Int(dede) {
            biliMid = mid
            defaults.set(mid, forKey: "biliMid")
        }
        biliPhase = .loggedIn
        NCLog.log("B站网页登录成功: \(webCookies.keys.sorted().joined(separator: ","))")
        Task {
            if let account = try? await biliClient.account() {
                biliUname = account.uname
                biliMid = account.mid
                defaults.set(account.mid, forKey: "biliMid")
                NCLog.log("B站账号: \(account.uname) mid=\(account.mid)")
            }
        }
    }

    struct LyricLine: Identifiable, Equatable {
        var id: Int
        var time: Double
        var text: String
        var translation: String
    }

    /// 系统音量镜像(主联动方案, 无需权限): 系统音量 → App 音量。
    @Published var systemVolumeMirror = true {
        didSet {
            defaults.set(systemVolumeMirror, forKey: "volumeMirror")
            if systemVolumeMirror && !previewMode { volumeMirror.start() } else { volumeMirror.stop() }
        }
    }
    let volumeMirror = VolumeMirror()
    /// 用户手动拖动 App 滑条后的抑制窗口(此期间镜像不覆盖)。
    private var manualVolumeAt: Date?

    let player = ExclusivePlayer()
    private var client: NCClient
    private let defaults: UserDefaults
    /// 预览/截图模式: 不枚举或占用音频设备、不启动音量镜像与媒体键轮询, 只用于渲染界面。
    /// Debug 下由 `UIPreviewStudio` 使用, Release 构建中恒为 false。
    private let previewMode: Bool
    private var qrKey: String?
    private var qrPollTask: Task<Void, Never>?
    private(set) var playbackTask: Task<Void, Never>?
    private var playbackRequestID = UUID()
    private var lyricsTask: Task<Void, Never>?
    /// 下载依赖可替换，便于验证乱序完成和取消，无需启动音频设备。
    var downloadAudio: (String, String, [String: String]) async throws -> URL = { url, format, headers in
        try await Downloader.ensureLocal(url: url, key: "", format: format, headers: headers)
    }
    /// 保留当前已加载音频，恢复播放不依赖正在浏览的列表或旧的远程链接。
    private struct LoadedPlayback {
        let url: URL
        let metadata: ExclusivePlayer.TrackStatus
    }
    private var loadedPlayback: LoadedPlayback?
    /// 测试可替换硬件边界；正常运行时由 ExclusivePlayer 播放。
    var startLocalAudio: ((URL, ExclusivePlayer.TrackStatus, Double?) -> Void)?
    var outputDeviceSnapshot: (() -> [AudioDeviceInfo])?
#if DEBUG
    /// 预览/截图用的假二维码内容(不发起网络请求)。
    fileprivate var previewLoginQRContent: String?
#endif

    var isLoggedIn: Bool { profile != nil }
    /// 是否已拿到登录 Cookie(即使界面还在登录中)。
    var hasMusicU: Bool { client.isLoggedIn }
    /// 当前播放条目封面(网易云取曲目封面, 其他来源取条目封面)。
    var currentCoverURL: String {
        if let item = currentItem { return item.coverURL }
        guard currentIndex >= 0, tracks.indices.contains(currentIndex) else { return "" }
        return tracks[currentIndex].coverURL
    }
    var currentSourceLabel: String {
        if let item = currentItem { return item.source.rawValue }
        return currentPlaylist != nil ? "网易云·歌单" : "网易云"
    }

    init(defaults: UserDefaults = .standard, previewMode: Bool = false) {
        self.defaults = defaults
        self.previewMode = previewMode
        let cookies = (defaults.dictionary(forKey: "cookies") as? [String: String]) ?? [:]
        let deviceId = defaults.string(forKey: "deviceId")
        client = NCClient(cookies: cookies, deviceId: deviceId)
        biliClient = BiliClient(cookies: (defaults.dictionary(forKey: "biliCookies") as? [String: String]) ?? [:])
        // 已默认关闭: 该功能在拔插时对 coreaudiod 扰动过大, 且静音+音量键拦截已覆盖其作用
        blockOtherOutputs = defaults.bool(forKey: "blockOtherOutputs")
        player.blockOtherOutputs = blockOtherOutputs
        autoDevice = !defaults.bool(forKey: "devicePinned")
        if !previewMode { setupHotplugListener() }
        biliMid = defaults.integer(forKey: "biliMid")
        if biliClient.isLoggedIn && !previewMode {
            biliPhase = .loggedIn
            Task {
                if let account = try? await biliClient.account() {
                    biliUname = account.uname
                    biliMid = account.mid
                    defaults.set(account.mid, forKey: "biliMid")
                }
            }
        }
        if let raw = defaults.string(forKey: "level"), let saved = NCLevel(rawValue: raw) {
            level = saved
        }
        // 安全默认: 10% 音量起步(位完美需要时用户自己拉满)
        let savedVolume = defaults.object(forKey: "volume") == nil ? 0.1 : defaults.double(forKey: "volume")
        volume = savedVolume.isFinite ? Float(min(max(savedVolume, 0), 1)) : 0.1
        player.volume = volume
        networkMode = NetworkMode.load(from: defaults)
        autoResume = defaults.object(forKey: "autoResume") == nil ? true : defaults.bool(forKey: "autoResume")
        // 系统音量 → App 音量镜像(0.4s 轮询, 拖动滑条后 2 秒内不覆盖)
        volumeMirror.onSystemVolume = { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                // 插拔后的等待状态不接受系统设备的初始音量（USB 设备常报告 100%）。
                guard !self.outputNeedsUserPlay else { return }
                if let manualAt = self.manualVolumeAt,
                   Date().timeIntervalSince(manualAt) < 2.0 { return }
                self.volume = value
                if self.muteSystemWhileRunning && self.playbackActive {
                    self.applyMutePolicy()
                    self.systemMuteSession?.ensureMuted()
                    self.volumeMirror.rebase()
                }
            }
        }
        systemVolumeMirror = defaults.object(forKey: "volumeMirror") == nil || defaults.bool(forKey: "volumeMirror")
        if !previewMode && systemVolumeMirror { volumeMirror.start() }
        mediaKeyTap.onVolumeChange = { [weak self] delta in
            Task { @MainActor in
                guard let self else { return }
                self.setManualVolume(min(max(self.volume + delta, 0), 1))
            }
        }
        mediaKeyTap.onMuteToggle = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.setManualVolume(self.volume > 0 ? 0 : 0.1)
            }
        }
        mediaKeyTap.shouldInterceptVolume = { [weak self] in
            guard let self else { return false }
            return self.playbackActive
        }
        mediaKeyTap.onPlayPause = { [weak self] in
            Task { @MainActor in self?.playPause() }
        }
        mediaKeyTap.onNext = { [weak self] in
            Task { @MainActor in self?.playNext() }
        }
        mediaKeyTap.onPrevious = { [weak self] in
            Task { @MainActor in self?.playPrevious() }
        }
        if defaults.object(forKey: "muteSystem") == nil || defaults.bool(forKey: "muteSystem") {
            muteSystemWhileRunning = true   // 默认开启(实际静音动作跟随播放状态)
        }
        mediaControlKeysEnabled = defaults.bool(forKey: "mediaControlKeys")

        player.onStateChange = { [weak self] state in
            let playbackID = self?.player.playbackID
            Task { @MainActor in
                guard let self, self.playbackTask == nil, self.suspendedPlaybackPosition == nil,
                      self.player.playbackID == playbackID, self.player.state == state else { return }
                self.playerState = state
                self.applyMutePolicy()
                self.updateMediaKeyTap()
            }
        }
        player.onTrackChange = { [weak self] status in
            let playbackID = self?.player.playbackID
            Task { @MainActor in
                guard let self, self.playbackTask == nil, self.suspendedPlaybackPosition == nil,
                      self.player.playbackID == playbackID else { return }
                self.trackStatus = status
                if self.lyricIndex >= 0, self.lyricIndex < self.lyrics.count {
                    self.updateLyricIndex(position: status.positionSeconds)
                } else {
                    self.updateLyricIndex(position: status.positionSeconds)
                }
            }
        }
        player.onTrackFinished = { [weak self] in
            let playbackID = self?.player.playbackID
            Task { @MainActor in
                guard let self, self.playbackTask == nil, self.suspendedPlaybackPosition == nil,
                      self.player.playbackID == playbackID, self.player.state == .playing else { return }
                self.playNext(autoPlay: true)
            }
        }
        if !previewMode { refreshDevices() }
        isRestoringState = false

        // 用户去系统设置授权后回到净听时，重新检查权限并启用媒体键接管。
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateMediaKeyTap() }
            }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        permissionPollTimer?.invalidate()
    }

    // MARK: - 设备

    /// 自动模式优先外置输出；固定设备暂时离线时保留 UID，等待同一设备回来。
    @Published var autoDevice = true {
        didSet {
            defaults.set(!autoDevice, forKey: "devicePinned")
            if autoDevice {
                defaults.removeObject(forKey: "deviceUID")
                refreshDevices()
            }
        }
    }
    /// 插拔后引擎已释放，但曲目与进度仍可由用户点击播放继续。
    private(set) var suspendedPlaybackPosition: Double?
    private var outputNeedsUserPlay = false
    private var hotplugListener: AudioDevice.HotplugListener?
    private var hotplugDebounceTask: Task<Void, Never>?

    func refreshDevices() {
        if let outputDeviceSnapshot {
            reconcileDevices(outputDeviceSnapshot())
            return
        }
        guard !previewMode else { return }
        reconcileDevices(AudioDevice.allDevices(), defaultID: SystemOutput.defaultOutputDeviceID())
    }

    /// 接收同一次枚举的设备快照，避免枚举多次或递归刷新造成目标来回覆盖。
    func reconcileDevices(_ available: [AudioDeviceInfo], defaultID: UInt32? = nil) {
        devices = available
        let chosen: AudioDeviceInfo?
        if !autoDevice, let savedUID = defaults.string(forKey: "deviceUID") {
            chosen = available.first { $0.uid == savedUID }
        } else {
            chosen = AudioDevice.preferredOutput(in: available, defaultID: defaultID, preferredUID: selectedDevice?.uid)
        }
        let changed = selectedDevice?.uid != chosen?.uid || selectedDevice?.id != chosen?.id
            || player.deviceID != (chosen?.id ?? 0)
        guard changed else {
            selectedDevice = chosen // 采样率等显示信息可以刷新，不打断播放。
            return
        }
        suspendForOutputChange()
        selectedDevice = chosen
        player.deviceID = chosen?.id ?? 0
        NCLog.log("[设备] 输出变更 → \(chosen?.name ?? "设备离线")，等待用户播放；音量 \(Int(volume * 100))%")
    }

    private func suspendForOutputChange() {
        let hasTrack = loadedPlayback != nil || currentItem != nil || tracks.indices.contains(currentIndex)
            || !trackStatus.title.isEmpty
        let position = suspendedPlaybackPosition ?? trackStatus.positionSeconds
        let status = trackStatus
        cancelPendingPlayback() // 晚到的下载、解析和歌词也不能在设备恢复后启动播放。
        if !isRestoringState { outputNeedsUserPlay = true }
        suspendedPlaybackPosition = hasTrack ? position : nil
        player.stop() // 先释放旧设备；不会把声音接到扬声器或新插入的设备。
        trackStatus = status
        trackStatus.exclusive = false
        playerState = hasTrack ? .paused : .idle
        volume = min(volume, 0.1) // 保留静音和更低音量；新连接输出最多 10%。
        volumeMirror.rebase()
        applyMutePolicy()
        updateMediaKeyTap()
    }

    private func setupHotplugListener() {
        hotplugListener = AudioDevice.HotplugListener { [weak self] invalidatedDeviceID in
            self?.scheduleHotplugHandling(invalidatedDeviceID: invalidatedDeviceID)
        }
    }

    /// 拔出立即停止，插入等待事件稳定后再选择；两条路径都不启动播放。
    func scheduleHotplugHandling(invalidatedDeviceID: UInt32?) {
        volumeMirror.rebase()
        if let invalidatedDeviceID, invalidatedDeviceID == selectedDevice?.id {
            // 极快重插可能复用同一 ID + UID；alive/data-source 事件本身即令旧 IO 失效。
            suspendForOutputChange()
            selectedDevice = nil
            player.deviceID = 0
        }
        let available = outputDeviceSnapshot?() ?? (previewMode ? devices : AudioDevice.allDevices())
        if let selectedDevice,
           !available.contains(where: { $0.id == selectedDevice.id && $0.uid == selectedDevice.uid }) {
            reconcileDevices(available, defaultID: SystemOutput.defaultOutputDeviceID())
        }
        hotplugDebounceTask?.cancel()
        hotplugDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshDevices()
        }
    }

    func selectDevice(_ device: AudioDeviceInfo) {
        hotplugDebounceTask?.cancel()
        let changed = selectedDevice?.uid != device.uid || selectedDevice?.id != device.id
        if changed { suspendForOutputChange() }
        autoDevice = false
        defaults.set(device.uid, forKey: "deviceUID")
        selectedDevice = device
        player.deviceID = device.id
    }

    // MARK: - 登录

    func restoreSession() async {
        if client.isLoggedIn {
            await finishLogin()   // 单一收尾路径: 取账号+歌单(带重试)
            if profile != nil {
                if autoResume, !outputNeedsUserPlay, let lastId = defaults.object(forKey: "lastPlaylistId") as? Int,
                   let playlist = playlists.first(where: { $0.id == lastId }) {
                    await openPlaylist(playlist, autoPlay: true)
                }
                return
            }
            if client.isLoggedIn { return }   // cookie 还在但暂时取不到账号, 不清 cookie
        }
        startLoginPolling()
    }

    func startLoginPolling() {
        qrPollTask?.cancel()
        loginPhase = .idle
        qrPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let key = try await self.client.createLoginQRKey()
                    self.qrKey = key
                    self.loginPhase = .qrWaiting
                    // 轮询同一个 key; 连续无进展时退避, 避免触发网易风控惩罚
                    var idleRounds = 0
                    let keyCreatedAt = Date()
                    // 4 分钟轮换新码(服务器 5 分半过期), 界面二维码随 qrKey 自动刷新
                    while Date().timeIntervalSince(keyCreatedAt) < 240 {
                        if Task.isCancelled { return }
                        let interval: UInt64 = idleRounds >= 10 ? 6_000_000_000 : 3_000_000_000
                        try await Task.sleep(nanoseconds: interval + UInt64.random(in: 0...500_000_000))
                        guard let key = self.qrKey else { return }
                        let code = (try? await self.client.checkLoginQR(key: key)) ?? 801
                        NCLog.log("扫码轮询 code=\(code) 已持MUSIC_U=\(self.client.isLoggedIn)")
                        if code == 801 {
                            idleRounds += 1
                            if idleRounds == 10 { NCLog.log("  连续等待, 轮询退避至 6 秒") }
                        } else {
                            idleRounds = 0
                        }
                        switch code {
                        case 802:
                            self.loginPhase = .qrScanned
                        case 803:
                            await self.finishLogin()
                            return
                        default:
                            // 有些情况服务器只发 Cookie 不回 803, 以 MUSIC_U 为准
                            if self.client.isLoggedIn {
                                await self.finishLogin()
                                return
                            }
                        }
                        if code == 800 { break }   // 过期, 外层重建二维码
                    }
                } catch {
                    NCLog.log("二维码创建失败: \(error.localizedDescription)")
                    self.loginPhase = .failed("创建二维码失败, 3 秒后自动重试")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    var loginQRURL: String? {
#if DEBUG
        if let previewLoginQRContent { return previewLoginQRContent }
#endif
        guard let qrKey else { return nil }
        return client.loginQRURL + qrKey
    }

    /// 检测到登录 Cookie(MUSIC_U)后的收尾: 先持久化 cookie, 再带重试地取用户信息。
    private func finishLogin() async {
        loginPhase = .loggingIn
        NCLog.log("登录成功, 持久化 cookie")
        defaults.set(client.cookies, forKey: "cookies")
        defaults.set(client.deviceId, forKey: "deviceId")

        var profile: NCProfile?
        let retryDelays: [UInt64] = [1_500_000_000, 3_000_000_000, 5_000_000_000, 8_000_000_000]
        for (attempt, delay) in retryDelays.enumerated() {
            profile = try? await client.account()
            if profile != nil { break }
            NCLog.log("获取用户信息失败(第 \(attempt + 1) 次), \(delay / 1_000_000_000) 秒后重试")
            try? await Task.sleep(nanoseconds: delay)
        }
        if profile == nil { profile = try? await client.account() }   // 仅在仍未成功时补试
        guard let profile else {
            loginPhase = .failed("已授权但获取用户信息失败, 请点击重试")
            return
        }
        self.profile = profile
        loginPhase = .loggedIn
        qrPollTask?.cancel()
        NCLog.log("用户信息获取成功: \(profile.nickname) uid=\(profile.userId)")
        playlists = (try? await client.userPlaylists(uid: profile.userId)) ?? []
        NCLog.log("歌单加载完成, 共 \(playlists.count) 个")
    }

    /// 登录 Cookie 已在但用户信息失败时, 仅重试账号信息。
    func retryAccountOnly() async {
        loginPhase = .loggingIn
        for _ in 0..<5 {
            if let profile = try? await client.account() {
                self.profile = profile
                loginPhase = .loggedIn
                playlists = (try? await client.userPlaylists(uid: profile.userId)) ?? []
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        loginPhase = .failed("获取用户信息失败, 请检查网络后重试")
    }

    private func loginSucceededSimple(profile: NCProfile) async {
        self.profile = profile
        loginPhase = .loggedIn
        defaults.set(client.cookies, forKey: "cookies")
        defaults.set(client.deviceId, forKey: "deviceId")
        playlists = (try? await client.userPlaylists(uid: profile.userId)) ?? []
    }

    func logout() {
        cancelPendingPlayback()
        suspendedPlaybackPosition = nil
        loadedPlayback = nil
        player.stop()
        currentItem = nil
        itemQueue = []
        defaults.removeObject(forKey: "cookies")
        profile = nil
        playlists = []
        tracks = []
        currentPlaylist = nil
        currentIndex = -1
        client = NCClient()
        startLoginPolling()
    }

    // MARK: - 歌单与播放

    func openPlaylist(_ playlist: NCPlaylist, autoPlay: Bool = false) async {
        let requestID = playbackRequestID
        currentPlaylist = playlist
        defaults.set(playlist.id, forKey: "lastPlaylistId")
        tracks = []
        let loaded = (try? await client.playlistTracks(playlistId: playlist.id)) ?? []
        guard currentPlaylist?.id == playlist.id else { return }   // 防串台
        tracks = loaded
        if autoPlay, requestID == playbackRequestID, !loaded.isEmpty {
            play(index: 0)
        }
    }

    private func cancelPendingPlayback() {
        playbackRequestID = UUID()
        playbackTask?.cancel()
        playbackTask = nil
        lyricsTask?.cancel()
        quickPlayBusy = false
    }

    private func beginPlaybackRequest() -> UUID {
        cancelPendingPlayback()
        loadedPlayback = nil
        player.stop()
        loadingHint = ""
        return playbackRequestID
    }

    private func isCurrentPlayback(_ id: UUID) -> Bool {
        id == playbackRequestID && !Task.isCancelled
    }

    private func finishPlaybackRequest(_ id: UUID) {
        guard id == playbackRequestID else { return }
        playbackTask = nil
        quickPlayBusy = false
    }

    func play(index: Int, resumeAt: Double? = nil) {
        guard tracks.indices.contains(index) else { return }
        guard prepareOutputForPlayback() else { return }
        let requestID = beginPlaybackRequest()
        suspendedPlaybackPosition = nil
        currentItem = nil
        itemQueue = []
        currentIndex = index
        let track = tracks[index]
        fetchLyrics(for: track)
        playerState = .loading("取链中…")
        playbackTask = Task {
            defer { finishPlaybackRequest(requestID) }
            do {
                try Task.checkCancellation()
                var result = try await client.songURL(id: track.id, level: level)
                guard isCurrentPlayback(requestID) else { return }
                if result?.url?.isEmpty != false {
                    result = try await client.songURLFallback(id: track.id, level: level)
                }
                guard isCurrentPlayback(requestID) else { return }
                guard let result, let url = result.url, !url.isEmpty else {
                    playerState = .error("取不到音源(无版权或需 VIP)")
                    return
                }
                if let trial = result.freeTrialInfo { loadingHint = trial }
                playerState = .loading("下载 \(result.format.uppercased()) …")
                let local = try await downloadAudio(url, result.format, [:])
                guard isCurrentPlayback(requestID), tracks.indices.contains(index),
                      tracks[index].id == track.id else { return }
                var status = ExclusivePlayer.TrackStatus()
                status.title = track.name
                status.artist = track.artists
                status.format = result.format
                status.level = result.level
                beginLocalPlayback(url: local, metadata: status, resumeAt: resumeAt)
            } catch {
                guard isCurrentPlayback(requestID) else { return }
                playerState = .error("播放失败: \(error.localizedDescription)")
            }
        }
    }

    /// 播放一个已解析好的条目(网易/B站/直链)。
    func play(item: PlayableItem, resumeAt: Double? = nil) {
        guard prepareOutputForPlayback() else { return }
        let requestID = beginPlaybackRequest()
        suspendedPlaybackPosition = nil
        currentItem = item
        if !itemQueue.contains(where: { $0.id == item.id }) { itemQueue = [item] }
        currentIndex = -1
        lyrics = []
        lyricIndex = -1
        playerState = .loading("取链完成, 下载中…")
        playbackTask = Task {
            defer { finishPlaybackRequest(requestID) }
            do {
                try Task.checkCancellation()
                let local = try await downloadAudio(item.downloadURL, item.format, item.headers)
                guard isCurrentPlayback(requestID) else { return }
                var status = ExclusivePlayer.TrackStatus()
                status.title = item.title
                status.artist = item.artist
                status.format = item.format
                status.level = item.source.rawValue
                beginLocalPlayback(url: local, metadata: status, resumeAt: resumeAt)
            } catch {
                guard isCurrentPlayback(requestID) else { return }
                playerState = .error("播放失败: \(error.localizedDescription)")
            }
        }
    }

    /// 解析与下载共享请求身份；新的操作会取消旧的解析和下载。
    func resolveAndPlay(_ input: String, coverFallback: String = "") {
        quickPlayError = nil
        guard let (kind, value) = SourceResolver.classify(input) else {
            quickPlayError = "无法识别: 支持网易云歌曲链接/ID、B站链接/BV号、音频直链"
            return
        }
        guard prepareOutputForPlayback() else { return }
        let requestID = beginPlaybackRequest()
        suspendedPlaybackPosition = nil
        quickPlayBusy = true
        playerState = .loading("解析来源…")
        playbackTask = Task {
            defer { finishPlaybackRequest(requestID) }
            do {
                try Task.checkCancellation()
                var items: [PlayableItem]
                switch kind {
                case "netease":
                    guard let id = Int(value) else { throw URLError(.badURL) }
                    items = [try await SourceResolver.resolveNetease(id: id, client: client, level: level)]
                case "bilibili":
                    items = try await SourceResolver.resolveBilibili(value, bili: biliClient)
                case "direct":
                    items = [SourceResolver.resolveDirect(value)]
                default: throw URLError(.badURL)
                }
                guard isCurrentPlayback(requestID), !items.isEmpty else { return }
                if items[0].coverURL.isEmpty { items[0].coverURL = coverFallback }
                itemQueue = items
                play(item: items[0])
            } catch {
                guard isCurrentPlayback(requestID) else { return }
                playerState = .error(error.localizedDescription)
                quickPlayError = error.localizedDescription
            }
        }
    }

    func playNext(autoPlay: Bool = true) {
        if let item = currentItem {
            guard let index = itemQueue.firstIndex(where: { $0.id == item.id }) else { return }
            if itemQueue.indices.contains(index + 1) { play(item: itemQueue[index + 1]) }
            else if autoPlay { cancelPendingPlayback(); player.stop() }
            return
        }
        guard !tracks.isEmpty else { return }
        let next = currentIndex + 1
        if next < tracks.count { play(index: next) }
        else if autoPlay { cancelPendingPlayback(); player.stop() }
    }

    /// 点播前重新核对当前设备，不能在断开与防抖之间向旧 ID 输出。
    private func prepareOutputForPlayback() -> Bool {
        refreshDevices()
        guard (previewMode && outputDeviceSnapshot == nil) || selectedDevice != nil else {
            playerState = .error("输出设备未就绪，请连接后点击播放")
            NCLog.log("[播放控制] 设备未就绪，保留恢复进度")
            return false
        }
        volumeMirror.rebase()
        player.volume = volume
        outputNeedsUserPlay = false
        return true
    }

    /// 下载完成与断线后的本地恢复共用入口；调用方已确认设备与请求身份。
    func beginLocalPlayback(url: URL, metadata: ExclusivePlayer.TrackStatus, resumeAt: Double?) {
        loadedPlayback = LoadedPlayback(url: url, metadata: metadata)
        if let startLocalAudio {
            startLocalAudio(url, metadata, resumeAt)
            return
        }
        player.playFile(url: url, metadata: metadata)
        if let resumeAt, resumeAt > 0 { player.seek(to: resumeAt) }
        synchronizePlayerState()
    }

    private func synchronizePlayerState() {
        playerState = player.state
        trackStatus = player.trackStatus
        applyMutePolicy()
        updateMediaKeyTap()
    }

    func playPause() {
        NCLog.log("[播放控制] 点击：界面=\(playerState) 引擎=\(player.state) 等待重连=\(suspendedPlaybackPosition != nil) 本地音频=\(loadedPlayback != nil)")
        // 请求与引擎状态是执行依据；界面状态可能尚未收到旧设备的异步回调。
        if playbackTask != nil {
            cancelPendingPlayback()
            player.stop()
            playerState = .idle
            applyMutePolicy()
            updateMediaKeyTap()
            return
        }
        if player.state == .playing, suspendedPlaybackPosition == nil {
            player.pause()
            synchronizePlayerState()
            return
        }
        let position = suspendedPlaybackPosition ?? trackStatus.positionSeconds
        guard prepareOutputForPlayback() else { return }
        if player.state == .paused, suspendedPlaybackPosition == nil {
            player.resume()
            synchronizePlayerState()
            return
        }
        if let loaded = loadedPlayback, FileManager.default.fileExists(atPath: loaded.url.path) {
            _ = beginPlaybackRequest()
            suspendedPlaybackPosition = nil
            NCLog.log("[播放控制] 从本地音频重建输出，进度=\(position)")
            beginLocalPlayback(url: loaded.url, metadata: loaded.metadata, resumeAt: position)
        } else if let item = currentItem {
            play(item: item, resumeAt: position)
        } else if !tracks.isEmpty {
            play(index: min(max(currentIndex, 0), tracks.count - 1), resumeAt: position)
        } else {
            playerState = .error("当前音频不可用，请重新选择一首歌")
        }
    }

    func playPrevious() {
        if let item = currentItem {
            guard let index = itemQueue.firstIndex(where: { $0.id == item.id }) else { return }
            play(item: itemQueue[max(index - 1, 0)])
            return
        }
        guard !tracks.isEmpty else { return }
        play(index: max(currentIndex - 1, 0))
    }

    // MARK: - B站登录

    func startBiliLogin() {
        biliPollTask?.cancel()
        biliPhase = .idle
        biliQRURL = nil
        biliPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let (url, key) = try await self.biliClient.createLoginQR()
                    self.biliQRURL = url
                    self.biliPhase = .qrWaiting
                    let createdAt = Date()
                    while Date().timeIntervalSince(createdAt) < 170 {
                        if Task.isCancelled { return }
                        try await Task.sleep(nanoseconds: 2_500_000_000)
                        let code = (try? await self.biliClient.pollLoginQR(key: key)) ?? 86101
                        NCLog.log("B站扫码轮询 code=\(code)")
                        switch code {
                        case 0:
                            guard self.biliClient.isLoggedIn else {
                                NCLog.log("⚠ B站返回成功但未捕获到 Cookie")
                                self.biliPhase = .failed("登录成功但 Cookie 未捕获, 请重试")
                                return
                            }
                            self.defaults.set(self.biliClient.cookies, forKey: "biliCookies")
                            // mid 优先从 Cookie 补, 再查 nav
                            if let dede = self.biliClient.cookies["DedeUserID"], let mid = Int(dede) {
                                self.biliMid = mid
                                self.defaults.set(mid, forKey: "biliMid")
                            }
                            if let account = try? await self.biliClient.account() {
                                self.biliUname = account.uname
                                self.biliMid = account.mid
                                self.defaults.set(account.mid, forKey: "biliMid")
                                NCLog.log("B站账号: \(account.uname) mid=\(account.mid)")
                            }
                            self.biliPhase = .loggedIn
                            return
                        case 86090:
                            self.biliPhase = .qrScanned
                        case 86038:
                            continue   // 过期, 外层重建
                        default:
                            break
                        }
                    }
                } catch {
                    NCLog.log("B站登录错误: \(error.localizedDescription)")
                    self.biliPhase = .failed("网络错误, 3 秒后重试")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    /// 取消扫码登录, 回到选择界面。
    func cancelBiliLogin() {
        biliPollTask?.cancel()
        biliPollTask = nil
        biliQRURL = nil
        biliPhase = .idle
    }

    func logoutBili() {
        biliClient.logout()
        defaults.removeObject(forKey: "biliCookies")
        biliPhase = .idle
        biliUname = ""
    }

    /// 把搜索到的歌临时加入当前队列(追加到"搜索结果歌单")。
    func appendTrack(_ track: NCTrack) -> Int {
        if currentPlaylist == nil || tracks.isEmpty {
            // 建一个虚拟"搜索结果"队列
            currentPlaylist = NCPlaylist(id: -1, name: "搜索结果", coverUrl: "", trackCount: 0, playCount: 0)
            tracks = []
        }
        tracks.append(track)
        return tracks.count - 1
    }

    // MARK: - 搜索

    func doSearch() {
        let keyword = searchKeyword.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        searchBusy = true
        Task {
            defer { searchBusy = false }
            searchResults = (try? await client.search(keyword: keyword)) ?? []
            NCLog.log("搜索「\(keyword)」→ \(searchResults.count) 首")
        }
    }

    // MARK: - 歌词

    func fetchLyrics(for track: NCTrack) {
        lyricsTask?.cancel()
        lyrics = []
        lyricIndex = -1
        guard track.id != 0 else { return }
        lyricsTask = Task {
            guard let result = try? await client.lyrics(id: track.id), !Task.isCancelled,
                  currentItem == nil, tracks.indices.contains(currentIndex),
                  tracks[currentIndex].id == track.id else { return }
            parseLyrics(result.lrc, translation: result.tlyric)
        }
    }

    /// 解析 lrc 并按时间戳合并翻译(tlyric)。
    func parseLyrics(_ lrc: String, translation tlyric: String?) {
        func parse(_ text: String) -> [(time: Double, text: String)] {
            let regex = (try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#))!
            var result: [(Double, String)] = []
            for raw in text.components(separatedBy: "\n") {
                let ns = raw as NSString
                let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
                guard let m = matches.first else { continue }
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                let body = regex.stringByReplacingMatches(in: raw, options: [],
                                                          range: NSRange(location: 0, length: ns.length),
                                                          withTemplate: "").trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { continue }
                result.append((min * 60 + sec, body))
            }
            return result
        }

        let main = parse(lrc)
        guard !main.isEmpty else { return }
        var translations: [Int: String] = [:]
        if let tlyric, !tlyric.isEmpty {
            let trans = parse(tlyric)
            for (time, text) in trans {
                translations[Int(time * 10)] = text   // 0.1s 粒度对齐
            }
        }
        lyrics = main.enumerated().map { index, line in
            let key = Int(line.0 * 10)
            let translation = translations[key]
                ?? translations[key - 1]
                ?? translations[key + 1]
                ?? ""
            return LyricLine(id: index, time: line.0, text: line.1, translation: translation)
        }
        .sorted { $0.time < $1.time }
    }

    private func updateLyricIndex(position: Double) {
        guard !lyrics.isEmpty else { return }
        var index = -1
        for (i, line) in lyrics.enumerated() where line.time <= position + 0.3 {
            index = i
        }
        if index != lyricIndex { lyricIndex = index }
    }

    /// 拖动进度。
    func seek(to seconds: Double) {
        if suspendedPlaybackPosition != nil {
            guard seconds.isFinite else { return }
            suspendedPlaybackPosition = min(max(seconds, 0), max(trackStatus.seconds, 0))
            trackStatus.positionSeconds = suspendedPlaybackPosition ?? 0
            return
        }
        player.seek(to: seconds)
        trackStatus.positionSeconds = seconds
    }

    // MARK: - 其他

    var cacheSizeText: String {
        let bytes = Downloader.cacheSizeBytes()
        let mb = Double(bytes) / 1_048_576
        return mb > 1 ? String(format: "%.0f MB", mb) : "< 1 MB"
    }

    func clearCache() {
        Downloader.clearCache()
        objectWillChange.send()
    }

    func shutdown() {
        cancelPendingPlayback()
        qrPollTask?.cancel()
        biliPollTask?.cancel()
        hotplugDebounceTask?.cancel()
        hotplugListener?.stop()
        hotplugListener = nil
        stopPermissionPolling()
        volumeMirror.stop()
        mediaKeyTap.isEnabled = false
        player.shutdown()
        systemMuteSession?.restore()
        systemMuteSession = nil
    }
}

#if DEBUG
// MARK: - 预览注入(Debug)

extension AppState {
    /// 截图: 直接给登录页一个可渲染的二维码, 不请求网易接口。
    func previewSetLoginQR(_ content: String?) {
        previewLoginQRContent = content
    }

    /// 截图: 直接给 B 站登录页一个可渲染的二维码。
    func previewSetBiliQR(_ content: String?) {
        biliQRURL = content
        if content != nil { biliPhase = .qrWaiting }
    }
}
#endif
