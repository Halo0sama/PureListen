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

    @Published var level: NCLevel = .lossless
    @Published var volume: Float = 1.0 {
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
        playerState = .loading("解析 B 站音频…")
        quickPlayError = nil
        Task {
            do {
                let items = try await SourceResolver.resolveBilibili(video.bvid, bili: biliClient)
                // 用收藏夹条目的封面/UP主名(更准)
                var first = items[0]
                if first.coverURL.isEmpty { first.coverURL = video.cover }
                itemQueue = items
                play(item: first)
            } catch {
                playerState = .error(error.localizedDescription)
                quickPlayError = error.localizedDescription
            }
        }
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
    private var wasMutedBeforeUs = false
    private var weMutedSystem = false

    private var playbackActive: Bool {
        switch playerState {
        case .playing, .loading: return true
        default: return false
        }
    }

    /// 静音策略: 播放(独占)中→系统静音; 暂停/停止→还原。
    private var permissionPromptShown = false

    private func updateMediaKeyTap() {
        let need = playbackActive || mediaControlKeysEnabled
        let permitted = MediaKeyTap.hasPermission()
        mediaKeyTap.isEnabled = need && permitted
        if need && !permitted {
            if !permissionPromptShown {
                permissionPromptShown = true
                NCLog.log("[媒体键] ⚠ 无辅助功能权限, 本次启动仅提示一次")
                MediaKeyTap.requestPermission()
            }
            NCLog.log("[媒体键] ⚠ 无辅助功能权限, 音量键拦截未生效; 若设置里已开启但仍弹窗, 请关闭再打开一次开关(重新构建后签名变化会导致授权失效)")
        }
    }

    private func applyMutePolicy() {
        if muteSystemWhileRunning && playbackActive {
            if !SystemMute.isMuted() {
                wasMutedBeforeUs = false
                SystemMute.setMuted(true)
                weMutedSystem = true
                NCLog.log("[静音] 播放中, 系统已静音(挡其他 App 漏音)")
            }
        } else if weMutedSystem {
            if !wasMutedBeforeUs {
                SystemMute.setMuted(false)
                NCLog.log("[静音] 播放结束, 系统声音已恢复")
            }
            weMutedSystem = false
        }
    }

    /// 接管 播放/暂停/上一曲/下一曲 媒体键。
    @Published var mediaControlKeysEnabled = false {
        didSet {
            defaults.set(mediaControlKeysEnabled, forKey: "mediaControlKeys")
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
            if systemVolumeMirror { volumeMirror.start() } else { volumeMirror.stop() }
        }
    }
    let volumeMirror = VolumeMirror()
    /// 用户手动拖动 App 滑条后的抑制窗口(此期间镜像不覆盖)。
    private var manualVolumeAt: Date?

    let player = ExclusivePlayer()
    private var client: NCClient
    private let defaults = UserDefaults.standard
    private var qrKey: String?
    private var qrPollTask: Task<Void, Never>?

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

    init() {
        let cookies = (defaults.dictionary(forKey: "cookies") as? [String: String]) ?? [:]
        let deviceId = defaults.string(forKey: "deviceId")
        client = NCClient(cookies: cookies, deviceId: deviceId)
        biliClient = BiliClient(cookies: (defaults.dictionary(forKey: "biliCookies") as? [String: String]) ?? [:])
        // 已默认关闭: 该功能在拔插时对 coreaudiod 扰动过大, 且静音+音量键拦截已覆盖其作用
        blockOtherOutputs = defaults.bool(forKey: "blockOtherOutputs")
        player.blockOtherOutputs = blockOtherOutputs
        autoDevice = !defaults.bool(forKey: "devicePinned")
        setupHotplugListener()
        biliMid = defaults.integer(forKey: "biliMid")
        if biliClient.isLoggedIn {
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
        volume = Float(defaults.double(forKey: "volume") == 0 ? 0.1 : defaults.double(forKey: "volume"))
        autoResume = defaults.bool(forKey: "autoResume")
        // 系统音量 → App 音量镜像(0.4s 轮询, 拖动滑条后 2 秒内不覆盖)
        volumeMirror.onSystemVolume = { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                if let manualAt = self.manualVolumeAt,
                   Date().timeIntervalSince(manualAt) < 2.0 { return }
                self.volume = value
                // 播放中若用户按音量键解除了静音, 重新拉起(百分比已生效, 挡漏音继续)
                if self.muteSystemWhileRunning && self.playbackActive && !SystemMute.isMuted() {
                    SystemMute.setMuted(true)
                    NCLog.log("[静音] 播放中检测到解除静音, 已重新静音(音量已联动)")
                }
            }
        }
        if defaults.object(forKey: "volumeMirror") == nil || defaults.bool(forKey: "volumeMirror") {
            systemVolumeMirror = true   // 默认开启
        }
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
            Task { @MainActor in
                guard let self else { return }
                self.playerState = state
                self.applyMutePolicy()
                self.updateMediaKeyTap()
            }
        }
        player.onTrackChange = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.trackStatus = status
                if self.lyricIndex >= 0, self.lyricIndex < self.lyrics.count {
                    self.updateLyricIndex(position: status.positionSeconds)
                } else {
                    self.updateLyricIndex(position: status.positionSeconds)
                }
            }
        }
        player.onTrackFinished = { [weak self] in
            Task { @MainActor in self?.playNext(autoPlay: true) }
        }
        refreshDevices()
    }

    // MARK: - 设备

    /// 设备是否自动跟随(耳机优先); 手动指定设备时为 false。
    @Published var autoDevice = true {
        didSet {
            defaults.set(!autoDevice, forKey: "devicePinned")
            if autoDevice {
                defaults.removeObject(forKey: "deviceUID")
                refreshDevices()
            }
        }
    }

    func refreshDevices() {
        devices = AudioDevice.allDevices()
        let savedUID = defaults.string(forKey: "deviceUID")
        var chosen: AudioDeviceInfo?
        if let savedUID {
            if let match = devices.first(where: { $0.uid == savedUID }) {
                autoDevice = false
                chosen = match
            } else {
                // 固定的设备不存在(被拔出/更换): 回到自动模式
                defaults.removeObject(forKey: "deviceUID")
                autoDevice = true
                NCLog.log("[设备] 固定设备不存在, 已回到自动跟随")
            }
        }
        if chosen == nil { chosen = AudioDevice.preferredOutput() }
        if let chosen {
            selectedDevice = chosen
            player.deviceID = chosen.id
        }
    }

    /// 热插拔: 自动模式下跟随耳机, 并保留进度续播。
    private func setupHotplugListener() {
        AudioDevice.startDeviceHotplugListener { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleHotplugHandling()
            }
        }
    }

    /// 热插拔防抖: 事件风暴合并为一次处理(插拔常触发一串设备列表事件)。
    private var hotplugDebounceTask: Task<Void, Never>?
    private var lastPlaybackRestartAt = Date.distantPast

    private func scheduleHotplugHandling() {
        hotplugDebounceTask?.cancel()
        hotplugDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // 1.2s 静默期后处理
            guard !Task.isCancelled else { return }
            self?.handleHotplug()
        }
    }

    private func handleHotplug() {
        let wasActive: Bool
        switch playerState {
        case .playing, .paused: wasActive = true
        case .loading: wasActive = true
        default: wasActive = false
        }
        let oldUID = selectedDevice?.uid
        refreshDevices()
        guard let now = selectedDevice, now.uid != oldUID else {
            if wasActive, case .error = playerState {
                restartPlaybackOnDeviceIfAny()
            }
            return
        }
        NCLog.log("[设备] 热插拔: \(oldUID ?? "无") → \(now.name) 自动跟随=\(autoDevice ? "是" : "否")")
        if wasActive || currentItem != nil || currentIndex >= 0 {
            restartPlaybackOnDeviceIfAny()
        }
    }

    /// 在当前选定设备上重启播放(记忆进度)。
    private func restartPlaybackOnDeviceIfAny() {
        // 限流: 3 秒内的重复重启直接跳过(设备抖动会连发事件)
        guard Date().timeIntervalSince(lastPlaybackRestartAt) > 3.0 else {
            NCLog.log("[设备] 重启限流生效, 跳过本次")
            return
        }
        lastPlaybackRestartAt = Date()
        let resumeAt = trackStatus.positionSeconds
        player.stop()
        player.deviceID = selectedDevice?.id ?? 0
        guard player.deviceID != 0 else { return }
        if let item = currentItem {
            play(item: item, resumeAt: resumeAt)
        } else if currentIndex >= 0, tracks.indices.contains(currentIndex) {
            play(index: currentIndex, resumeAt: resumeAt)
        }
    }

    func selectDevice(_ device: AudioDeviceInfo) {
        autoDevice = false
        selectedDevice = device
        player.deviceID = device.id
        defaults.set(device.uid, forKey: "deviceUID")
        // 切设备后重播当前曲目
        if currentIndex >= 0, tracks.indices.contains(currentIndex) {
            play(index: currentIndex)
        }
    }

    // MARK: - 登录

    func restoreSession() async {
        if client.isLoggedIn {
            await finishLogin()   // 单一收尾路径: 取账号+歌单(带重试)
            if profile != nil {
                if autoResume, let lastId = defaults.object(forKey: "lastPlaylistId") as? Int,
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
        player.stop()
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
        currentPlaylist = playlist
        defaults.set(playlist.id, forKey: "lastPlaylistId")
        tracks = []
        let loaded = (try? await client.playlistTracks(playlistId: playlist.id)) ?? []
        guard currentPlaylist?.id == playlist.id else { return }   // 防串台
        tracks = loaded
        if autoPlay, !loaded.isEmpty {
            play(index: 0)
        }
    }

    func play(index: Int, resumeAt: Double? = nil) {
        guard tracks.indices.contains(index) else { return }
        currentItem = nil
        currentIndex = index
        let track = tracks[index]
        fetchLyrics(for: track)
        playerState = .loading("取链中…")
        Task {
            do {
                var result = try await client.songURL(id: track.id, level: level)
                if result == nil {
                    result = try await client.songURLFallback(id: track.id, level: level)
                }
                guard let result, let url = result.url, !url.isEmpty else {
                    playerState = .error("取不到音源(无版权或需 VIP)")
                    return
                }
                if let trial = result.freeTrialInfo {
                    loadingHint = trial
                }
                playerState = .loading("下载 \(result.format.uppercased()) …")
                let local = try await Downloader.ensureLocal(url: url,
                                                              key: url.md5Prefix,
                                                              format: result.format)
                guard currentIndex == index else { return }   // 已切歌
                var status = ExclusivePlayer.TrackStatus()
                status.title = track.name
                status.artist = track.artists
                status.format = result.format
                status.level = result.level
                player.playFile(url: local, metadata: status)
                if let resumeAt, resumeAt > 0.5 {
                    player.seek(to: resumeAt)
                }
            } catch {
                playerState = .error("播放失败: \(error.localizedDescription)")
            }
        }
    }

    /// 播放一个已解析好的条目(网易/B站/直链)。
    func play(item: PlayableItem, resumeAt: Double? = nil) {
        currentItem = item
        lyrics = []
        lyricIndex = -1
        playerState = .loading("取链完成, 下载中…")
        Task {
            do {
                let key = item.downloadURL.md5PrefixSafe
                let local = try await Downloader.ensureLocal(url: item.downloadURL, key: key,
                                                              format: item.format,
                                                              headers: item.headers)
                var status = ExclusivePlayer.TrackStatus()
                status.title = item.title
                status.artist = item.artist
                status.format = item.format
                status.level = item.source.rawValue
                player.playFile(url: local, metadata: status)
                if let resumeAt, resumeAt > 0.5 {
                    player.seek(to: resumeAt)
                }
            } catch {
                playerState = .error("播放失败: \(error.localizedDescription)")
            }
        }
    }

    /// 解析用户输入并播放(支持 网易ID/歌曲链接、B站BV/av/链接/b23短链、音频直链)。
    func resolveAndPlay(_ input: String) {
        quickPlayError = nil
        guard let (kind, value) = SourceResolver.classify(input) else {
            quickPlayError = "无法识别: 支持网易云歌曲链接/ID、B站链接/BV号、音频直链"
            return
        }
        quickPlayBusy = true
        playerState = .loading("解析来源…")
        Task {
            defer { quickPlayBusy = false }
            do {
                switch kind {
                case "netease":
                    if let id = Int(value) {
                        let item = try await SourceResolver.resolveNetease(id: id, client: client, level: level)
                        itemQueue = [item]
                        play(item: item)
                    } else {
                        quickPlayError = "网易链接里没找到歌曲 ID"
                    }
                case "bilibili":
                    let items = try await SourceResolver.resolveBilibili(value, bili: biliClient)
                    itemQueue = items
                    play(item: items[0])
                case "direct":
                    let item = SourceResolver.resolveDirect(value)
                    itemQueue = [item]
                    play(item: item)
                default:
                    quickPlayError = "未知来源"
                }
            } catch {
                playerState = .error(error.localizedDescription)
                quickPlayError = error.localizedDescription
            }
        }
    }

    func playNext(autoPlay: Bool = true) {
        guard !tracks.isEmpty else { return }
        let next = currentIndex + 1
        if next < tracks.count {
            play(index: next)
        } else if autoPlay {
            player.stop()
        }
    }
    func playPause() {
        switch playerState {
        case .playing: player.pause()
        case .paused: player.resume()
        default:
            if currentIndex < 0, !tracks.isEmpty { play(index: 0) }
        }
    }


    func playPrevious() {
        guard !tracks.isEmpty else { return }
        let prev = currentIndex - 1
        if prev >= 0 { play(index: prev) } else { play(index: 0) }
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
        lyrics = []
        lyricIndex = -1
        guard track.id != 0 else { return }
        Task {
            guard let result = try? await client.lyrics(id: track.id) else { return }
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
        qrPollTask?.cancel()
        player.shutdown()
        if weMutedSystem, !wasMutedBeforeUs {
            SystemMute.setMuted(false)   // 退出时还原系统声音
        }
    }
}

private extension String {
    /// 用直链路径里的文件名(md5)做缓存 key; 必须剥离查询串(vuutv 里含斜杠且每次变化)。
    var md5Prefix: String {
        guard let comps = URLComponents(string: self),
              let last = comps.path.split(separator: "/").last,
              let name = String(last).split(separator: ".").first, !name.isEmpty else {
            return UUID().uuidString
        }
        return String(name)
    }

    /// 任意直链的安全缓存 key(路径名优先, 兜底 URL 哈希)。
    var md5PrefixSafe: String {
        if let comps = URLComponents(string: self),
           let last = comps.path.split(separator: "/").last,
           let name = String(last).split(separator: ".").first, !name.isEmpty, name.count <= 128 {
            return String(name)
        }
        return String(abs(hashValue))
    }
}
