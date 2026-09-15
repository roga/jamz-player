import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum MetadataReader {
    static func read(from url: URL) async -> SongMetadata {
        let asset = AVURLAsset(url: url)
        var metadata = SongMetadata()
        // AVFoundation maps ID3v2.3/v2.4 text frames to these common keys.
        // A missing or broken tag must not prevent importing valid audio.
        let items = (try? await asset.load(.commonMetadata)) ?? []
        for item in items {
            guard !Task.isCancelled else { return metadata }
            switch item.commonKey {
            case .commonKeyTitle:
                metadata.title = try? await item.load(.stringValue)
            case .commonKeyArtist:
                metadata.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName:
                metadata.album = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                if metadata.artwork == nil, let data = try? await item.load(.dataValue) {
                    metadata.artwork = normalizedArtwork(data)
                }
            default: break
            }
        }
        return metadata
    }

    /// Decode thumbnails off the UI actor and store one bounded-size JPEG.
    /// Invalid artwork falls back to the default cover without rejecting the song.
    static func normalizedArtwork(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1000
              ] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }
}
