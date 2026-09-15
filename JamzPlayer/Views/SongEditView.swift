import SwiftUI

struct SongEditView: View {
    let song: Song
    let onSave: (String, String, String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(song: Song, onSave: @escaping (String, String, String) async -> String?) {
        self.song = song
        self.onSave = onSave
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
        _album = State(initialValue: song.album)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("歌名", text: $title)
                TextField("演出者", text: $artist)
                TextField("專輯", text: $album)
            }
            .disabled(isSaving)
            .navigationTitle("編輯歌曲")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "儲存中…" : "儲存") {
                        isSaving = true
                        Task { @MainActor in
                            errorMessage = await onSave(title, artist, album)
                            isSaving = false
                            if errorMessage == nil { dismiss() }
                        }
                    }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("無法儲存歌曲", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
