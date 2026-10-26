import XCTest
@testable import PureListen
@testable import PureListenCore

@MainActor
final class PlaybackQueueTests: XCTestCase {
    private func track(_ id: Int) -> NCTrack {
        NCTrack(id: id, name: "Song \(id)", artists: "Artist \(id)", album: "Album \(id)",
                durationMs: 120000, vipOnly: false, coverURL: "https://example.test/cover/\(id)")
    }
    private func playlist(_ id: Int) -> NCPlaylist {
        NCPlaylist(id: id, name: "List \(id)", coverUrl: "list:\(id)", trackCount: 3, playCount: 0)
    }
    private func fixture() throws -> (AppState, UserDefaults, String, URL) {
        let suite = "PureListen.queue.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let state = AppState(defaults: defaults, previewMode: true)
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("isolated local audio boundary".utf8).write(to: audio)
        state.songURLRequest = { id, _ in
            NCSongURL(json: ["url": "https://example.test/\(id).flac", "type": "flac", "level": "lossless"])
        }
        state.downloadAudio = { _, _, _ in audio }
        state.startLocalAudio = { [weak state] _, status, _ in
            state?.trackStatus = status; state?.playerState = .playing
        }
        return (state, defaults, suite, audio)
    }
    private func clean(_ state: AppState, _ defaults: UserDefaults, _ suite: String, _ audio: URL) {
        state.shutdown(); defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: audio)
    }

    func testBrowsingAnotherListCannotChangeArtworkNextPreviousOrSourceQueue() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        state.currentPlaylist = playlist(1); state.tracks = [track(1), track(2), track(3)]
        state.play(index: 1); await state.playbackTask?.value
        state.currentPlaylist = playlist(2); state.tracks = [track(99)]
        XCTAssertEqual(state.currentCoverURL, track(2).coverURL)
        XCTAssertEqual(state.trackStatus.title, "Song 2")
        XCTAssertEqual(state.playbackPlaylist?.id, 1)
        XCTAssertEqual(state.nextPlaybackTitle, "Song 3 · Artist 3")
        state.playNext(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, 3)
        XCTAssertEqual(state.currentCoverURL, track(3).coverURL)
        state.playPrevious(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, 2)
        XCTAssertEqual(state.tracks.map(\.id), [99])
        XCTAssertEqual(state.currentPlaylist?.id, 2)
        XCTAssertEqual(defaults.integer(forKey: "lastPlaylistId"), 1)
    }

    func testBrowsingDuringSourceRequestKeepsSelectedTrackAndMetadata() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        let started = expectation(description: "URL request started")
        var pending: CheckedContinuation<NCSongURL?, Error>?
        state.songURLRequest = { _, _ in
            try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        state.currentPlaylist = playlist(1); state.tracks = [track(7)]
        state.play(index: 0)
        let task = try XCTUnwrap(state.playbackTask)
        await fulfillment(of: [started], timeout: 2)
        state.currentPlaylist = playlist(2); state.tracks = [track(8)]
        XCTAssertEqual(state.currentCoverURL, track(7).coverURL)
        XCTAssertEqual(state.trackStatus.title, "Song 7")
        pending?.resume(returning: NCSongURL(json: ["url": "https://example.test/7.flac", "type": "flac"]))
        await task.value
        XCTAssertEqual(state.playingTrack?.id, 7)
        XCTAssertEqual(state.trackStatus.title, "Song 7")
        XCTAssertEqual(state.playbackTracks.map(\.id), [7])
    }

    func testSearchPlaybackDoesNotAppendToBrowsedPlaylist() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        state.currentPlaylist = playlist(9); state.tracks = [track(90)]
        state.searchResults = [track(10), track(11)]
        state.playSearchTrack(track(10)); await state.playbackTask?.value
        state.searchResults = [track(20)]
        XCTAssertNil(state.playbackPlaylist)
        XCTAssertEqual(state.currentSourceLabel, "网易云")
        state.playNext(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, 11)
        XCTAssertEqual(state.tracks.map(\.id), [90])
        XCTAssertEqual(state.currentPlaylist?.id, 9)
    }

    func testRepeatAllWrapsButManualNextOverridesRepeatOne() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        state.tracks = [track(1), track(2)]; state.playbackMode = .repeatAll
        state.play(index: 1); await state.playbackTask?.value
        state.playNext(autoPlay: true); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, 1)
        state.playPrevious(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, 2)
        state.playbackMode = .repeatOne
        state.playNext(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, 1)
    }

    func testRepeatOneReusesLoadedAudioInsteadOfDownloadingAgain() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        var downloads = 0, starts = 0
        var resumedAt: Double?
        state.downloadAudio = { _, _, _ in downloads += 1; return audio }
        state.startLocalAudio = { [weak state] _, status, position in
            starts += 1; resumedAt = position; state?.trackStatus = status
        }
        state.tracks = [track(1), track(2)]
        state.play(index: 0); await state.playbackTask?.value
        state.playbackMode = .repeatOne
        state.playNext(autoPlay: true)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(resumedAt, 0)
        XCTAssertEqual(state.playingTrack?.id, 1)
        XCTAssertEqual(state.currentCoverURL, track(1).coverURL)
    }

    func testShuffleVisitsWholeQueueAndPreviousUsesActualHistory() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        state.tracks = (1...5).map(track)
        state.playbackMode = .shuffle
        state.play(index: 0); await state.playbackTask?.value
        var played = [try XCTUnwrap(state.playingTrack?.id)]
        for _ in 0..<4 {
            state.playNext(autoPlay: true); await state.playbackTask?.value
            played.append(try XCTUnwrap(state.playingTrack?.id))
        }
        XCTAssertEqual(Set(played), Set(1...5))
        state.playPrevious(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, played[3])
        state.playNext(); await state.playbackTask?.value
        XCTAssertEqual(state.playingTrack?.id, played[4])
        state.playNext(); await state.playbackTask?.value
        XCTAssertNotEqual(state.playingTrack?.id, played[4])
    }

    func testBiliQueueAndArtworkRemainAfterBrowsingAnotherFolder() throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        let video = BiliClient.FavVideo(id: 1, bvid: "BV1xx411c7mD", title: "Video", cover: "cover:first", upper: "UP", durationSeconds: 10)
        state.favVideos = [video]
        state.playBiliVideo(video)
        state.favVideos = []
        state.tracks = [track(88)]; state.currentPlaylist = playlist(8)
        XCTAssertEqual(state.currentCoverURL, "cover:first")
        XCTAssertEqual(state.currentItem?.title, "Video")
        XCTAssertEqual(state.itemQueue.count, 1)
        XCTAssertEqual(state.currentSourceLabel, "哔哩哔哩")
        XCTAssertNil(state.playingTrack)
    }

    func testNaturalRepeatNeverRestartsAfterDeviceIntervention() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        let dac = AudioDeviceInfo(id: 201, uid: "test-dac", name: "DAC", isBuiltIn: false,
                                  currentRate: 48000, hasOutput: true)
        state.reconcileDevices([dac])
        state.tracks = [track(1), track(2)]
        state.play(index: 0); await state.playbackTask?.value
        state.trackStatus.positionSeconds = 12
        state.playbackMode = .repeatOne
        state.reconcileDevices([]); state.reconcileDevices([dac])
        state.playNext(autoPlay: true)
        XCTAssertNil(state.playbackTask)
        XCTAssertEqual(state.playerState, .paused)
        XCTAssertEqual(state.suspendedPlaybackPosition, 12)
        XCTAssertEqual(state.playingTrack?.id, 1)
        XCTAssertEqual(state.volume, 0.1)
    }

    func testOfflineNextDoesNotConsumeShuffleChoice() async throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        let dac = AudioDeviceInfo(id: 201, uid: "test-dac", name: "DAC", isBuiltIn: false,
                                  currentRate: 48000, hasOutput: true)
        var available = [dac]
        state.outputDeviceSnapshot = { available }
        state.refreshDevices(); state.tracks = [track(1), track(2), track(3)]
        state.play(index: 0); await state.playbackTask?.value
        state.playbackMode = .shuffle
        let queued = state.nextPlaybackTitle
        available = []; state.refreshDevices()
        state.playNext()
        XCTAssertEqual(state.nextPlaybackTitle, queued)
        XCTAssertEqual(state.playingTrack?.id, 1)
        available = [dac]; state.refreshDevices()
        state.playNext(); await state.playbackTask?.value
        XCTAssertEqual("Song \(state.playingTrack!.id) · Artist \(state.playingTrack!.id)", queued)
    }

    func testPlaybackModePersistsWithoutChangingVolume() throws {
        let (state, defaults, suite, audio) = try fixture()
        defer { clean(state, defaults, suite, audio) }
        state.volume = 0; state.playbackMode = .shuffle
        let restored = AppState(defaults: defaults, previewMode: true)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.playbackMode, .shuffle)
        XCTAssertEqual(restored.volume, 0)
    }
}
