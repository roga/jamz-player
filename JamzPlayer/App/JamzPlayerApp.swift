import SwiftUI

@main
struct JamzPlayerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library: LibraryStore
    @StateObject private var player: PlayerStore

    init() {
        let repository = LibraryRepository()
        _library = StateObject(wrappedValue: LibraryStore(repository: repository))
        _player = StateObject(wrappedValue: PlayerStore(repository: repository))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library, player: player)
            .tint(JamzTheme.accent)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { player.refreshState() }
            }
        }
    }
}
