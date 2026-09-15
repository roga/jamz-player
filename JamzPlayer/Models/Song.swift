import Foundation

struct Song: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let filename: String
    var title: String
    var artist: String
    var album: String
    var artworkFilename: String?
    let duration: TimeInterval
    let importedAt: Date
}

struct SongMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: Data?

    func resolvedTitle(filename: String) -> String {
        Self.nonEmpty(title) ?? Self.nonEmpty((filename as NSString).deletingPathExtension) ?? "未命名歌曲"
    }
    var resolvedArtist: String { Self.nonEmpty(artist) ?? "未知演出者" }
    var resolvedAlbum: String { Self.nonEmpty(album) ?? "未知專輯" }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
