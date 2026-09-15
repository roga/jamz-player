import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isMutating = false
    var isBusy: Bool { isImporting || isMutating }
    @Published private(set) var progress: Double?
    @Published private(set) var status = ""
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?
    @Published var showsImport = false

    let repository: LibraryRepository
    private var importTask: Task<Void, Never>?
    private var importID: UUID?

    init(repository: LibraryRepository = LibraryRepository()) {
        self.repository = repository
    }

    func load() async {
        guard !isLoaded else { return }
        do {
            songs = try await repository.load()
            isLoaded = true
        } catch { errorMessage = ImportError.libraryUnavailable.localizedDescription }
    }

    func startImport(_ address: String) {
        guard !isBusy, isLoaded else { return }
        let url: URL
        do { url = try HTTPSURLPolicy.validate(address) }
        catch { errorMessage = ImportError.message(for: error); return }
        isImporting = true
        progress = nil
        status = "正在下載…"
        let id = UUID()
        importID = id
        importTask = Task { [self] in
            defer {
                isImporting = false
                progress = nil
                importID = nil
                importTask = nil
            }
            do {
                let downloader = HTTPSDownloader { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.importID == id, self.status == "正在下載…" else { return }
                        self.progress = progress
                    }
                }
                let file = try await downloader.download(from: url)
                defer { try? FileManager.default.removeItem(at: file.url) }
                try Task.checkCancellation()
                progress = nil
                status = "正在檢查音檔並儲存…"
                songs = try await repository.importFile(file)
                showsImport = false
            } catch is CancellationError {
                status = "已取消匯入"
            } catch let error as URLError where error.code == .cancelled {
                status = "已取消匯入"
            } catch {
                errorMessage = ImportError.message(for: error)
            }
        }
    }

    func edit(_ song: Song, title: String, artist: String, album: String) async -> String? {
        guard isLoaded, !isBusy else { return LibraryMutationError.busy.localizedDescription }
        isMutating = true
        defer { isMutating = false }
        do {
            songs = try await repository.edit(song.id, title: title, artist: artist, album: album)
            return nil
        } catch { return mutationMessage(error) }
    }

    func delete(_ song: Song) async {
        guard isLoaded, !isBusy else {
            errorMessage = LibraryMutationError.busy.localizedDescription
            return
        }
        isMutating = true
        defer { isMutating = false }
        do { songs = try await repository.delete(song.id) }
        catch { errorMessage = mutationMessage(error) }
    }

    private func mutationMessage(_ error: Error) -> String {
        if case LibraryMutationError.recovery = error { isLoaded = false }
        return (error as? LibraryMutationError)?.localizedDescription ?? LibraryMutationError.storage.localizedDescription
    }

    func cancelImport() { importTask?.cancel() }
}
