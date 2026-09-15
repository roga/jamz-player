import Foundation

struct SleepTimerState {
    static let presets = [15, 30, 60]
    private(set) var deadline: TimeInterval?

    mutating func set(minutes: Int, now: TimeInterval) {
        guard Self.presets.contains(minutes) else { return }
        deadline = now + Double(minutes * 60)
    }

    mutating func cancel() { deadline = nil }

    func remaining(at now: TimeInterval) -> TimeInterval? {
        deadline.map { max(0, $0 - now) }
    }

    mutating func consumeExpiry(at now: TimeInterval) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil
        return true
    }
}

enum PlaybackClock {
    private static let origin = ContinuousClock.now
    static func now() -> TimeInterval {
        let components = origin.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
