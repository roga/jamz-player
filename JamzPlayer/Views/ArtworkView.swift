import SwiftUI

struct ArtworkView: View {
    let url: URL?

    var body: some View {
        Group {
            #if os(iOS)
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image("DefaultArtwork").resizable().scaledToFill() }
            #else
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else { Image("DefaultArtwork").resizable().scaledToFill() }
            #endif
        }
        .clipped()
        .accessibilityHidden(true)
    }


}

enum PlaybackTime {
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
