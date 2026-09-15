import SwiftUI

enum JamzTheme {
    static let accent = Color(red: 1, green: 0.52, blue: 0.31)
    static let background = Color(red: 0.055, green: 0.06, blue: 0.075)
    static let surface = Color(red: 0.095, green: 0.10, blue: 0.12)
}

struct JamzBackground: View {
    var body: some View {
        ZStack {
            JamzTheme.background
            RadialGradient(colors: [JamzTheme.accent.opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
        }.ignoresSafeArea()
    }
}
