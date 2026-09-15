import Foundation
import AVFoundation
import Combine

@MainActor
final class PlayerStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var sleepRemaining: TimeInterval?

    let repository: LibraryRepository
    private var audio: AVAudioPlayer?
    private var queue: [Song] = []
    private var ticker: Timer?
    private var sleepTimer = SleepTimerState()
    private let now: () -> TimeInterval
    #if os(iOS)
    private lazy var systemPlayback = SystemPlaybackBridge(
        onPlay: { [weak self] in self?.resume() },
        onPause: { [weak self] in self?.pause() },
        onToggle: { [weak self] in self?.toggle() },
        onNext: { [weak self] in self?.next() },
        onPrevious: { [weak self] in self?.previous() },
        onSeek: { [weak self] in self?.seek(to: $0) },
        onReset: { [weak self] in self?.resetAudioService() }
    )
    #endif

    init(repository: LibraryRepository, now: @escaping () -> TimeInterval = PlaybackClock.now) {
        self.repository = repository
        self.now = now
        super.init()
        #if os(iOS)
        _ = systemPlayback
        #endif
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    deinit { ticker?.invalidate() }

    func updateQueue(_ songs: [Song]) {
        queue = songs
        guard let id = currentSong?.id else { return }
        if let updated = songs.first(where: { $0.id == id }) {
            currentSong = updated
            updateSystemPlayback()
        } else {
            audio?.stop()
            audio = nil
            currentSong = nil
            isPlaying = false
            position = 0
            duration = 0
            errorMessage = nil
            cancelSleepTimer()
            updateSystemPlayback()
            #if os(iOS)
            systemPlayback.deactivate()
            #endif
        }
    }

    func select(_ song: Song, songs: [Song]) {
        queue = songs
        start(song)
    }

    private func start(_ song: Song) {
        guard !stopIfSleepExpired() else { return }
        do {
            let next = try AVAudioPlayer(contentsOf: repository.audioURL(for: song))
            guard next.prepareToPlay() else { throw ImportError.invalidMP3 }
            audio?.stop()
            audio = next
            next.delegate = self
            currentSong = song
            duration = next.duration
            position = 0
            resume()
        } catch {
            pause()
            errorMessage = "無法播放「\(song.title)」，請確認本機音檔仍存在且未損毀。"
        }
    }

    func toggle() { isPlaying ? pause() : resume() }

    func resume() {
        guard !stopIfSleepExpired() else { return }
        guard let audio else { return }
        #if os(iOS)
        do { try systemPlayback.activate() }
        catch {
            isPlaying = false
            errorMessage = "無法啟動音訊播放，請稍後重試。"
            return
        }
        #endif
        if audio.currentTime >= audio.duration - 0.05 { audio.currentTime = 0 }
        isPlaying = audio.play()
        position = audio.currentTime
        if !isPlaying { errorMessage = "目前無法播放音樂，請稍後重試。" }
        updateSystemPlayback()
    }

    func pause() {
        audio?.pause()
        isPlaying = false
        position = audio?.currentTime ?? position
        updateSystemPlayback()
        #if os(iOS)
        systemPlayback.deactivate()
        #endif
    }

    func seek(to time: TimeInterval) {
        guard let audio else { return }
        audio.currentTime = min(max(0, time), duration)
        position = audio.currentTime
        updateSystemPlayback()
    }

    func previous() {
        guard let currentSong, let index = queue.firstIndex(where: { $0.id == currentSong.id }) else { return }
        if position > 3 { seek(to: 0) }
        else if let previous = PlaybackPolicy.previousIndex(current: index, count: queue.count, mode: repeatMode) {
            if previous == index { seek(to: 0) }
            else { start(queue[previous]) }
        }
    }

    func next() {
        advance(naturalEnd: false)
    }

    private func advance(naturalEnd: Bool) {
        guard !stopIfSleepExpired() else { return }
        guard let currentSong, let index = queue.firstIndex(where: { $0.id == currentSong.id }),
              let next = PlaybackPolicy.nextIndex(current: index, count: queue.count,
                                                  mode: repeatMode, naturalEnd: naturalEnd) else { return }
        start(queue[next])
    }

    private func tick() {
        guard !stopIfSleepExpired() else { return }
        sleepRemaining = sleepTimer.remaining(at: now())
        if let audio, isPlaying { position = audio.currentTime }
        updateSystemPlayback()
    }

    func refreshState() { tick() }

    func setSleepTimer(minutes: Int) {
        sleepTimer.set(minutes: minutes, now: now())
        sleepRemaining = sleepTimer.remaining(at: now())
    }

    func cancelSleepTimer() {
        sleepTimer.cancel()
        sleepRemaining = nil
    }

    @discardableResult
    private func stopIfSleepExpired() -> Bool {
        guard sleepTimer.consumeExpiry(at: now()) else { return false }
        sleepRemaining = nil
        pause()
        return true
    }

    private func updateSystemPlayback() {
        #if os(iOS)
        systemPlayback.update(song: currentSong, artworkURL: currentSong.flatMap { repository.artworkURL(for: $0) },
                              duration: duration, position: position, playing: isPlaying)
        #endif
    }

    private func resetAudioService() {
        pause()
        audio = nil
        currentSong = nil
        position = 0
        duration = 0
        cancelSleepTimer()
        updateSystemPlayback()
        errorMessage = "系統音訊服務已重啟，請重新選擇歌曲播放。"
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player, self.isPlaying else { return }
            guard !self.stopIfSleepExpired() else { return }
            self.isPlaying = false
            self.position = self.duration
            if flag { self.advance(naturalEnd: true) }
            else { self.errorMessage = "音檔播放中斷，請重新選擇歌曲。" }
            self.updateSystemPlayback()
            #if os(iOS)
            if !self.isPlaying { self.systemPlayback.deactivate() }
            #endif
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            self.pause()
            self.errorMessage = "音檔無法解碼，請確認檔案是否完整。"
        }
    }
}
