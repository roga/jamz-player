#if os(iOS)
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class SystemPlaybackBridge {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var observers: [NSObjectProtocol] = []
    private var artworkSongID: UUID?
    private var artwork: MPMediaItemArtwork?

    init(onPlay: @escaping @MainActor @Sendable () -> Void, onPause: @escaping @MainActor @Sendable () -> Void,
         onToggle: @escaping @MainActor @Sendable () -> Void, onNext: @escaping @MainActor @Sendable () -> Void,
         onPrevious: @escaping @MainActor @Sendable () -> Void, onSeek: @escaping @MainActor @Sendable (Double) -> Void,
         onReset: @escaping @MainActor @Sendable () -> Void) {
        let commands = MPRemoteCommandCenter.shared()
        register(commands.playCommand, action: onPlay)
        register(commands.pauseCommand, action: onPause)
        register(commands.togglePlayPauseCommand, action: onToggle)
        register(commands.stopCommand, action: onPause)
        register(commands.nextTrackCommand, action: onNext)
        register(commands.previousTrackCommand, action: onPrevious)
        let token = commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in onSeek(time) }
            return .success
        }
        targets.append((commands.changePlaybackPositionCommand, token))
        targets.forEach { $0.0.isEnabled = false }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in onPause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in onPause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in onReset() }
        })
    }

    deinit {
        targets.forEach { $0.0.removeTarget($0.1) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor @Sendable () -> Void) {
        let target = command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
        targets.append((command, target))
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func update(song: Song?, artworkURL: URL?, duration: Double, position: Double, playing: Bool) {
        targets.forEach { $0.0.isEnabled = song != nil }
        guard let song else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        if artworkSongID != song.id {
            artworkSongID = song.id
            let image = artworkURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage(named: "DefaultArtwork")
            artwork = image.map { image in MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
#endif
