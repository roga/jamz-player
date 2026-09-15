import Foundation

enum RepeatMode: String, CaseIterable, Identifiable {
    case off, one, all
    var id: Self { self }
    var title: String {
        switch self {
        case .off: return "關閉循環"
        case .one: return "單曲循環"
        case .all: return "全部循環"
        }
    }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

enum PlaybackPolicy {
    static func nextIndex(current: Int, count: Int, mode: RepeatMode, naturalEnd: Bool) -> Int? {
        guard count > 0, (0..<count).contains(current) else { return nil }
        if naturalEnd, mode == .one { return current }
        if current + 1 < count { return current + 1 }
        return mode == .all ? 0 : nil
    }

    static func previousIndex(current: Int, count: Int, mode: RepeatMode) -> Int? {
        guard count > 0, (0..<count).contains(current) else { return nil }
        if current > 0 { return current - 1 }
        return mode == .all ? count - 1 : 0
    }
}
