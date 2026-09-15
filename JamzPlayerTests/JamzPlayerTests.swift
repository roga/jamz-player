import XCTest
import AVFoundation
#if os(iOS)
import MediaPlayer
#endif
@testable import JamzPlayer

final class JamzPlayerTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "mp3", subdirectory: "Fixtures"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jamz-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func repositoryWithTwoSongs() async throws -> (LibraryRepository, [Song]) {
        let repository = LibraryRepository(directory: try temporaryDirectory())
        let file = DownloadedFile(url: try fixture("silence"), suggestedName: "測試.mp3")
        _ = try await repository.importFile(file)
        let songs = try await repository.importFile(file)
        return (repository, songs)
    }

    private func audioBytes(_ data: Data) -> Data {
        guard data.starts(with: Data("ID3".utf8)) else { return data }
        let size = data[6..<10].reduce(0) { ($0 << 7) | Int($1) }
        return Data(data.dropFirst(10 + size))
    }

    func testEditsWriteChineseTagsAndPreserveAudioAndArtwork() async throws {
        for name in ["id3v23", "id3v24", "untagged"] {
            let repository = LibraryRepository(directory: try temporaryDirectory())
            let imported = try await repository.importFile(DownloadedFile(url: try fixture(name), suggestedName: "test.mp3"))
            let song = try XCTUnwrap(imported.first)
            let url = repository.audioURL(for: song)
            let before = try Data(contentsOf: url)
            let artwork = try repository.artworkURL(for: song).map { try Data(contentsOf: $0) }
            let metadataBefore = await MetadataReader.read(from: url)
            let result = try await repository.edit(song.id, title: "新的歌名🎵", artist: "新的演出者", album: "新的專輯")
            let metadata = await MetadataReader.read(from: url)
            XCTAssertEqual(metadata.title, "新的歌名🎵")
            XCTAssertEqual(metadata.artist, "新的演出者")
            XCTAssertEqual(metadata.album, "新的專輯")
            XCTAssertEqual(metadata.artwork, metadataBefore.artwork)
            XCTAssertEqual(audioBytes(before), audioBytes(try Data(contentsOf: url)))
            XCTAssertEqual(try repository.artworkURL(for: song).map { try Data(contentsOf: $0) }, artwork)
            XCTAssertGreaterThan(try MP3Inspector.duration(of: url), 1)
            let reloaded = try await repository.load()
            XCTAssertEqual(result, reloaded)
            XCTAssertEqual(result.first?.id, song.id)
            XCTAssertEqual(result.first?.title, "新的歌名🎵")
            XCTAssertFalse(FileManager.default.fileExists(atPath: repository.directory.appendingPathComponent("pending-mutation.json").path))
        }
    }

    func testWriterPreservesUnrelatedFramesAndRejectsUnsafeTags() throws {
        var original = try Data(contentsOf: fixture("id3v24"))
        let custom = Data([84, 88, 88, 88, 0, 0, 0, 5, 0, 0, 3, 120, 0, 121, 0])
        let oldSize = original[6..<10].reduce(0) { ($0 << 7) | Int($1) }
        original.insert(contentsOf: custom, at: 10)
        let newSize = oldSize + custom.count
        for i in 0..<4 { original[6 + i] = UInt8((newSize >> ((3 - i) * 7)) & 127) }
        let edited = try MP3MetadataWriter.updating(original, title: "新", artist: "人", album: "輯")
        XCTAssertNotNil(edited.range(of: custom))
        for version: UInt8 in [2, 5] {
            var unsafe = original
            unsafe[3] = version
            XCTAssertThrowsError(try MP3MetadataWriter.updating(unsafe, title: "a", artist: "b", album: "c"))
        }
        var flagged = original
        flagged[5] = 0x80
        XCTAssertThrowsError(try MP3MetadataWriter.updating(flagged, title: "a", artist: "b", album: "c"))
        XCTAssertThrowsError(try MP3MetadataWriter.updating(Data(original.prefix(12)), title: "a", artist: "b", album: "c"))
    }

    @MainActor
    func testEditingCurrentSongKeepsPlaybackAndRefreshesSystemInfo() async throws {
        let (repository, songs) = try await repositoryWithTwoSongs()
        let song = songs[0]
        let player = PlayerStore(repository: repository)
        defer { player.pause() }
        player.select(song, songs: songs)
        XCTAssertTrue(player.isPlaying)
        player.seek(to: 0.5)
        let updated = try await repository.edit(song.id, title: "更新歌名", artist: "更新演出者", album: "更新專輯")
        player.updateQueue(updated)
        XCTAssertTrue(player.isPlaying)
        // MP3 seeking is quantized to audio frames. Allow one frame of tolerance.
        XCTAssertGreaterThanOrEqual(player.position, 0.47)
        XCTAssertEqual(player.currentSong?.title, "更新歌名")
        #if os(iOS)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "更新歌名")
        #endif
        player.pause()
        let pausedPosition = player.position
        let again = try await repository.edit(song.id, title: "暫停編輯", artist: "演出者", album: "專輯")
        player.updateQueue(again)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.position, pausedPosition)
        XCTAssertEqual(player.currentSong?.title, "暫停編輯")
    }

    func testDeleteRemovesOnlySelectedSongAndItsFiles() async throws {
        let repository = LibraryRepository(directory: try temporaryDirectory())
        let file = DownloadedFile(url: try fixture("id3v24"), suggestedName: "test.mp3")
        _ = try await repository.importFile(file)
        let songs = try await repository.importFile(file)
        let otherAudio = try Data(contentsOf: repository.audioURL(for: songs[1]))
        let result = try await repository.delete(songs[0].id)
        XCTAssertEqual(result, [songs[1]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.audioURL(for: songs[0]).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(repository.artworkURL(for: songs[0])).path))
        XCTAssertEqual(try Data(contentsOf: repository.audioURL(for: songs[1])), otherAudio)
        let reopened = LibraryRepository(directory: repository.directory)
        let loaded = try await reopened.load()
        XCTAssertEqual(loaded, result)
        let empty = try await repository.delete(songs[1].id)
        XCTAssertTrue(empty.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: repository.directory.path)
        XCTAssertEqual(files, ["library.json"])
    }

    @MainActor
    func testDeletingCurrentSongClearsPlayingAndPausedState() async throws {
        for paused in [false, true] {
            let (repository, songs) = try await repositoryWithTwoSongs()
            let player = PlayerStore(repository: repository)
            player.select(songs[0], songs: songs)
            player.seek(to: 0.5)
            player.setSleepTimer(minutes: 15)
            XCTAssertNotNil(player.sleepRemaining)
            if paused { player.pause() }
            let remaining = try await repository.delete(songs[0].id)
            player.updateQueue(remaining)
            XCTAssertNil(player.currentSong)
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(player.position, 0)
            XCTAssertEqual(player.duration, 0)
            XCTAssertNil(player.sleepRemaining)
            #if os(iOS)
            XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
            XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
            #endif
            player.resume()
            player.next()
            XCTAssertFalse(player.isPlaying)
            XCTAssertNil(player.currentSong)
        }
    }

    @MainActor
    func testDeletingOtherSongPreservesCurrentPlayback() async throws {
        let (repository, songs) = try await repositoryWithTwoSongs()
        let player = PlayerStore(repository: repository)
        defer { player.pause() }
        player.select(songs[0], songs: songs)
        player.seek(to: 0.5)
        player.setSleepTimer(minutes: 15)
        XCTAssertNotNil(player.sleepRemaining)
        let remaining = try await repository.delete(songs[1].id)
        player.updateQueue(remaining)
        XCTAssertEqual(player.currentSong?.id, songs[0].id)
        XCTAssertTrue(player.isPlaying)
        XCTAssertGreaterThanOrEqual(player.position, 0.47)
        XCTAssertNotNil(player.sleepRemaining)
        player.next()
        XCTAssertEqual(player.currentSong?.id, songs[0].id)
    }

    func testMutationFailuresRestoreOriginalFilesAndIndex() async throws {
        for operation in ["edit", "delete"] {
            for failure in [MutationFailureManager.Point.audio, .index, .commit] {
                let directory = try temporaryDirectory()
                let originalRepository = LibraryRepository(directory: directory)
                let songs = try await originalRepository.importFile(DownloadedFile(url: try fixture("id3v24"), suggestedName: "test.mp3"))
                let song = songs[0]
                let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                let originals = try Dictionary(uniqueKeysWithValues: names.map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
                let repository = LibraryRepository(directory: directory, manager: MutationFailureManager(point: failure))
                do {
                    if operation == "edit" { _ = try await repository.edit(song.id, title: "修改", artist: "人", album: "輯") }
                    else { _ = try await repository.delete(song.id) }
                    XCTFail("Expected simulated failure: \(operation) \(failure)")
                } catch { XCTAssertTrue(error is LibraryMutationError) }
                let restored = try await originalRepository.load()
                XCTAssertEqual(restored, songs)
                for (name, bytes) in originals {
                    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), bytes)
                }
                XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(names))
            }
        }
    }

    func testLoadRecoversInterruptedMutation() async throws {
        struct Backup: Codable { let name: String; let data: Data }
        let (repository, songs) = try await repositoryWithTwoSongs()
        let directory = repository.directory
        let names = [songs[0].filename, "library.json"]
        let originals = try names.map { Backup(name: $0, data: try Data(contentsOf: directory.appendingPathComponent($0))) }
        let journal = directory.appendingPathComponent("pending-mutation.json")
        try JSONEncoder().encode(originals).write(to: journal, options: .atomic)
        try FileManager.default.removeItem(at: repository.audioURL(for: songs[0]))
        try JSONEncoder().encode([songs[1]]).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        let reopened = LibraryRepository(directory: directory)
        let restored = try await reopened.load()
        XCTAssertEqual(restored, songs)
        for backup in originals { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup.name)), backup.data) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    @MainActor
    func testStoreRejectsOverlappingMutationsAndImport() async throws {
        let (repository, songs) = try await repositoryWithTwoSongs()
        let store = LibraryStore(repository: repository)
        await store.load()
        // Main-actor tasks are enqueued in order; the repository hop keeps the
        // first mutation pending when the second task attempts another action.
        let first = Task { await store.edit(songs[0], title: "第一筆", artist: "人", album: "輯") }
        let second = Task { @MainActor in
            XCTAssertTrue(store.isMutating)
            store.startImport("https://example.com/never-requested.mp3")
            XCTAssertFalse(store.isImporting)
            return await store.edit(songs[1], title: "不應儲存", artist: "人", album: "輯")
        }
        let firstError = await first.value
        let secondError = await second.value
        XCTAssertNil(firstError)
        XCTAssertEqual(secondError, LibraryMutationError.busy.localizedDescription)
        XCTAssertFalse(store.isMutating)
        let reloaded = try await repository.load()
        XCTAssertEqual(store.songs, reloaded)
        XCTAssertEqual(reloaded[0].title, "第一筆")
        XCTAssertEqual(reloaded[1], songs[1])
    }

    @MainActor
    func testStoreReportsFailedMutationAndPreservesPublishedSongs() async throws {
        let (repository, songs) = try await repositoryWithTwoSongs()
        let store = LibraryStore(repository: LibraryRepository(directory: repository.directory, manager: MutationFailureManager(point: .commit)))
        await store.load()
        await store.delete(songs[0])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.songs, songs)
        XCTAssertFalse(store.isMutating)
    }

    func testHTTPSURLValidation() throws {
        XCTAssertEqual(try HTTPSURLPolicy.validate("  https://example.com/song.mp3?token=test  ").scheme, "https")
        for url in ["http://example.com/a.mp3", "file:///a.mp3", "https://", "not a URL", "https://user:password@example.com/a.mp3"] {
            XCTAssertThrowsError(try HTTPSURLPolicy.validate(url))
        }
    }

    func testInsecureRedirectIsRejected() {
        let downloader = HTTPSDownloader(progress: { _ in })
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var redirected: URLRequest?
        downloader.urlSession(session, task: task, willPerformHTTPRedirection: response,
                              newRequest: URLRequest(url: URL(string: "http://example.com/song.mp3")!)) { redirected = $0 }
        XCTAssertNil(redirected)
        downloader.urlSession(session, task: task, willPerformHTTPRedirection: response,
                              newRequest: URLRequest(url: URL(string: "https://example.com/song.mp3")!)) { redirected = $0 }
        XCTAssertEqual(redirected?.url?.scheme, "https")
    }

    func testCancellationBeforeDownload() async throws {
        let operation = Task { () throws -> DownloadedFile in
            await Task.yield()
            return try await HTTPSDownloader(progress: { _ in }).download(from: URL(string: "https://example.com/song.mp3")!)
        }
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled download succeeded") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }

    func testNetworkFailureIsReturned() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        let downloader = HTTPSDownloader(configuration: configuration, progress: { _ in })
        do { _ = try await downloader.download(from: URL(string: "https://example.com/song.mp3")!); XCTFail("Expected offline error") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }

    func testErrorMessagesDoNotExposeDownloadURL() {
        let error = URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://example.com?secret=test"])
        XCTAssertEqual(ImportError.message(for: error), "下載逾時，請稍後再試。")
        XCTAssertTrue(ImportError.message(for: URLError(.networkConnectionLost)).contains("網路"))
        XCTAssertTrue(ImportError.message(for: ImportError.httpStatus(404)).contains("404"))
    }

    func testID3VersionsReadChineseMetadataAndArtwork() async throws {
        for filename in ["id3v23", "id3v24"] {
            let url = try fixture(filename)
            XCTAssertGreaterThan(try MP3Inspector.duration(of: url), 1.9)
            let metadata = await MetadataReader.read(from: url)
            XCTAssertEqual(metadata.title, "夜色節奏")
            XCTAssertEqual(metadata.artist, "Jamz 測試演出者")
            XCTAssertEqual(metadata.album, "離線時光")
            XCTAssertNotNil(metadata.artwork)
        }
    }

    func testMissingAndPartialMetadataFallback() async throws {
        let untagged = await MetadataReader.read(from: try fixture("untagged"))
        XCTAssertEqual(untagged.resolvedTitle(filename: "無標籤.mp3"), "無標籤")
        XCTAssertEqual(untagged.resolvedArtist, "未知演出者")
        XCTAssertEqual(untagged.resolvedAlbum, "未知專輯")
        XCTAssertNil(untagged.artwork)
        let partial = await MetadataReader.read(from: try fixture("partial"))
        XCTAssertEqual(partial.title, "只有歌名")
        XCTAssertEqual(partial.resolvedArtist, "未知演出者")
        XCTAssertEqual(partial.resolvedAlbum, "未知專輯")
        XCTAssertEqual(SongMetadata(title: " \n ").resolvedTitle(filename: "fallback.mp3"), "fallback")
        XCTAssertNil(MetadataReader.normalizedArtwork(Data("broken image".utf8)))
    }

    func testNonMP3AndCorruptAudioRejected() throws {
        XCTAssertThrowsError(try MP3Inspector.duration(of: fixture("invalid")))
        let root = try temporaryDirectory()
        let corrupt = root.appendingPathComponent("corrupt.mp3")
        try Data([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0, 0xFF, 0xFB]).write(to: corrupt)
        XCTAssertThrowsError(try MP3Inspector.duration(of: corrupt))
        let wav = root.appendingPathComponent("disguised.mp3")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        // A valid PCM container must not be accepted merely because it can play.
        let actualWAV = root.appendingPathComponent("tone.wav")
        do {
            let writer = try AVAudioFile(forWriting: actualWAV, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
            buffer.frameLength = 100
            memset(buffer.floatChannelData![0], 0, 100 * MemoryLayout<Float>.size)
            try writer.write(from: buffer)
        }
        try FileManager.default.copyItem(at: actualWAV, to: wav)
        XCTAssertThrowsError(try MP3Inspector.duration(of: wav))
    }

    func testLibrarySurvivesReloadAndSourceRemoval() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("download.mp3")
        try FileManager.default.copyItem(at: fixture("id3v24"), to: source)
        let directory = root.appendingPathComponent("library")
        let repository = LibraryRepository(directory: directory)
        let songs = try await repository.importFile(DownloadedFile(url: source, suggestedName: "test.mp3"))
        try FileManager.default.removeItem(at: source)
        let restored = try await LibraryRepository(directory: directory).load()
        XCTAssertEqual(restored, songs)
        XCTAssertEqual(restored.first?.title, "夜色節奏")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.audioURL(for: songs[0]).path))
        XCTAssertNotNil(repository.artworkURL(for: songs[0]))
        XCTAssertGreaterThan(try MP3Inspector.duration(of: repository.audioURL(for: songs[0])), 1.9)
    }

    func testFailedImportPreservesExistingLibrary() async throws {
        let (repository, before) = try await repositoryWithTwoSongs()
        let bytes = try Data(contentsOf: repository.directory.appendingPathComponent("library.json"))
        do {
            _ = try await repository.importFile(DownloadedFile(url: try fixture("invalid"), suggestedName: "bad.mp3"))
            XCTFail("Invalid import succeeded")
        } catch {}
        let after = try await repository.load()
        XCTAssertEqual(before, after)
        XCTAssertEqual(try Data(contentsOf: repository.directory.appendingPathComponent("library.json")), bytes)
    }

    func testIndexWriteFailureRollsBackCopiedFiles() async throws {
        let root = try temporaryDirectory()
        let manager = FailingIndexFileManager()
        let repository = LibraryRepository(directory: root, manager: manager)
        manager.directory = root
        do {
            _ = try await repository.save(DownloadedFile(url: try fixture("silence"), suggestedName: "test.mp3"),
                                          duration: 2, metadata: SongMetadata(artwork: Data([1, 2, 3])))
            XCTFail("Expected index write failure")
        } catch { XCTAssertTrue(error is ImportError) }
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(files, ["library.json"])
    }

    func testCorruptIndexIsNotOverwritten() async throws {
        let root = try temporaryDirectory()
        let index = root.appendingPathComponent("library.json")
        let bytes = Data("broken-index".utf8)
        try bytes.write(to: index)
        let repository = LibraryRepository(directory: root)
        do {
            _ = try await repository.save(DownloadedFile(url: try fixture("silence"), suggestedName: "test.mp3"),
                                          duration: 2, metadata: SongMetadata())
            XCTFail("Expected corrupt index error")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: index), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["library.json"])
    }

    func testRepeatModesAndManualSkip() {
        XCTAssertEqual(PlaybackPolicy.nextIndex(current: 0, count: 2, mode: .off, naturalEnd: true), 1)
        XCTAssertNil(PlaybackPolicy.nextIndex(current: 1, count: 2, mode: .off, naturalEnd: true))
        XCTAssertEqual(PlaybackPolicy.nextIndex(current: 0, count: 2, mode: .one, naturalEnd: true), 0)
        XCTAssertEqual(PlaybackPolicy.nextIndex(current: 0, count: 2, mode: .one, naturalEnd: false), 1)
        XCTAssertEqual(PlaybackPolicy.nextIndex(current: 1, count: 2, mode: .all, naturalEnd: true), 0)
        XCTAssertNil(PlaybackPolicy.nextIndex(current: 0, count: 0, mode: .all, naturalEnd: true))
        XCTAssertEqual(PlaybackPolicy.previousIndex(current: 0, count: 2, mode: .all), 1)
    }

    func testSleepPresetsResetCancellationAndOneShotExpiry() {
        for minutes in [15, 30, 60] {
            var timer = SleepTimerState()
            timer.set(minutes: minutes, now: 100)
            XCTAssertEqual(timer.remaining(at: 100), Double(minutes * 60))
            XCTAssertFalse(timer.consumeExpiry(at: 100 + Double(minutes * 60) - 0.001))
            XCTAssertTrue(timer.consumeExpiry(at: 100 + Double(minutes * 60)))
            XCTAssertNil(timer.deadline)
            XCTAssertFalse(timer.consumeExpiry(at: 99999))
        }
        var timer = SleepTimerState()
        timer.set(minutes: 15, now: 0)
        timer.set(minutes: 30, now: 40)
        XCTAssertEqual(timer.deadline, 1840)
        timer.cancel()
        XCTAssertFalse(timer.consumeExpiry(at: 99999))
        XCTAssertNil(SleepTimerState().deadline)
    }

    @MainActor
    func testPlayerPauseSkipSeekAndSleepDeadline() async throws {
        let (repository, songs) = try await repositoryWithTwoSongs()
        var now: TimeInterval = 0
        let player = PlayerStore(repository: repository, now: { now })
        defer { player.pause() }
        player.select(songs[0], songs: songs)
        XCTAssertTrue(player.isPlaying)
        player.setSleepTimer(minutes: 15)
        now = 60
        player.pause()
        player.refreshState()
        XCTAssertEqual(player.sleepRemaining, 840)
        player.next()
        XCTAssertEqual(player.currentSong?.id, songs[1].id)
        XCTAssertEqual(player.sleepRemaining, 840)
        player.seek(to: 0.5)
        XCTAssertEqual(player.position, 0.5, accuracy: 0.1)
        player.repeatMode = .all
        now = 900
        player.refreshState()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.sleepRemaining)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(player.isPlaying, "Repeat must not restart an expired sleep timer")
        let fresh = PlayerStore(repository: repository)
        XCTAssertNil(fresh.currentSong)
        XCTAssertNil(fresh.sleepRemaining)
        XCTAssertFalse(fresh.isPlaying)
    }

    @MainActor
    func testNaturalEndSingleAndAllRepeat() async throws {
        let (repository, songs) = try await repositoryWithTwoSongs()
        let player = PlayerStore(repository: repository)
        defer { player.pause() }
        for (mode, initial, expected, playing) in [(RepeatMode.off, 1, 1, false), (.one, 0, 0, true), (.all, 1, 0, true)] {
            player.repeatMode = mode
            player.select(songs[initial], songs: songs)
            player.seek(to: max(0, player.duration - 0.15))
            try await Task.sleep(for: .milliseconds(650))
            XCTAssertEqual(player.currentSong?.id, songs[expected].id)
            XCTAssertEqual(player.isPlaying, playing)
            player.pause()
        }
    }
}

private final class OfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

/// Fail after copying the audio, to exercise rollback rather than just a missing source.
private final class FailingIndexFileManager: FileManager, @unchecked Sendable {
    var directory: URL?
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        try super.createDirectory(at: directory!.appendingPathComponent("library.json"), withIntermediateDirectories: false)
    }
}

/// One-shot faults occur after real file operations, exercising rollback from
/// partially applied updates rather than just failing before anything changes.
private final class MutationFailureManager: FileManager, @unchecked Sendable {
    enum Point { case audio, index, commit }
    private let point: Point
    private let lock = NSLock()
    private var armed = true

    init(point: Point) { self.point = point; super.init() }

    private func shouldFail(_ url: URL, removal: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let matches: Bool
        switch point {
        case .audio: matches = url.pathExtension == "mp3"
        case .index: matches = !removal && url.lastPathComponent == "library.json"
        case .commit: matches = removal && url.lastPathComponent == "pending-mutation.json"
        }
        guard armed, matches else { return false }
        armed = false
        return true
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if shouldFail(URL(fileURLWithPath: path), removal: false) { throw CocoaError(.fileWriteNoPermission) }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }

    override func removeItem(at URL: URL) throws {
        if shouldFail(URL, removal: true) { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: URL)
    }
}
