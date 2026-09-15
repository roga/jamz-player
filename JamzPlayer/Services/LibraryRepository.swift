import Foundation

actor LibraryRepository {
    nonisolated let directory: URL
    private let manager: FileManager

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("JamzPlayer", isDirectory: true),
         manager: FileManager = .default) {
        self.directory = directory
        self.manager = manager
    }

    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    func load() throws -> [Song] {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        try recoverMutation()
        guard manager.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([Song].self, from: Data(contentsOf: indexURL))
    }

    private struct FileChange: Codable {
        let name: String
        let data: Data?
    }

    private var journalURL: URL { directory.appendingPathComponent("pending-mutation.json") }

    /// A durable undo journal survives app termination between file and index writes.
    /// Removing the journal is the commit point; recovery is safe to repeat.
    private func recoverMutation() throws {
        guard manager.fileExists(atPath: journalURL.path) else { return }
        do {
            let originals = try JSONDecoder().decode([FileChange].self, from: Data(contentsOf: journalURL))
            try apply(originals)
            try manager.removeItem(at: journalURL)
        } catch { throw LibraryMutationError.recovery }
    }

    private func validate(_ changes: [FileChange]) throws {
        guard Set(changes.map(\.name)).count == changes.count else { throw LibraryMutationError.storage }
        for change in changes {
            let name = change.name as NSString
            guard change.name == name.lastPathComponent,
                  change.name == "library.json" ||
                    (["mp3", "artwork"].contains(name.pathExtension) && UUID(uuidString: name.deletingPathExtension) != nil)
            else { throw LibraryMutationError.storage }
        }
    }

    private func apply(_ changes: [FileChange]) throws {
        try validate(changes)
        for change in changes {
            let url = directory.appendingPathComponent(change.name)
            if let data = change.data {
                try data.write(to: url, options: .atomic)
                #if os(iOS)
                try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                #endif
            } else if manager.fileExists(atPath: url.path) {
                try manager.removeItem(at: url)
            }
        }
    }

    private func commit(_ changes: [FileChange]) throws {
        try validate(changes)
        let originals = try changes.map { change in
            let url = directory.appendingPathComponent(change.name)
            return FileChange(name: change.name, data: manager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil)
        }
        do {
            try JSONEncoder().encode(originals).write(to: journalURL, options: .atomic)
            try apply(changes)
            try manager.removeItem(at: journalURL)
        } catch {
            try recoverMutation()
            throw LibraryMutationError.storage
        }
    }

    func edit(_ id: UUID, title: String, artist: String, album: String) throws -> [Song] {
        var songs = try load()
        guard let index = songs.firstIndex(where: { $0.id == id }) else { throw LibraryMutationError.missingSong }
        let song = songs[index]
        let audio = try MP3MetadataWriter.updating(Data(contentsOf: audioURL(for: song)), title: title, artist: artist, album: album)
        songs[index].title = title
        songs[index].artist = artist
        songs[index].album = album
        try commit([FileChange(name: song.filename, data: audio),
                    FileChange(name: "library.json", data: try JSONEncoder().encode(songs))])
        return songs
    }

    func delete(_ id: UUID) throws -> [Song] {
        var songs = try load()
        guard let index = songs.firstIndex(where: { $0.id == id }) else { throw LibraryMutationError.missingSong }
        let song = songs.remove(at: index)
        var changes = [FileChange(name: song.filename, data: nil)]
        if let artwork = song.artworkFilename, !songs.contains(where: { $0.artworkFilename == artwork }) {
            changes.append(FileChange(name: artwork, data: nil))
        }
        changes.append(FileChange(name: "library.json", data: try JSONEncoder().encode(songs)))
        try commit(changes)
        return songs
    }

    nonisolated func audioURL(for song: Song) -> URL {
        directory.appendingPathComponent(song.filename)
    }

    nonisolated func artworkURL(for song: Song) -> URL? {
        song.artworkFilename.map { directory.appendingPathComponent($0) }
    }

    func importFile(_ downloaded: DownloadedFile) async throws -> [Song] {
        let duration = try MP3Inspector.duration(of: downloaded.url)
        let metadata = await MetadataReader.read(from: downloaded.url)
        try Task.checkCancellation()
        return try save(downloaded, duration: duration, metadata: metadata)
    }

    /// Publish the index only after the audio and artwork are durable.
    /// Roll back new files on error; never overwrite the previous index with an empty library.
    func save(_ downloaded: DownloadedFile, duration: TimeInterval, metadata: SongMetadata) throws -> [Song] {
        var songs: [Song]
        do { songs = try load() }
        catch { throw ImportError.libraryUnavailable }
        let id = UUID()
        let audioName = "\(id.uuidString).mp3"
        let artworkName = metadata.artwork == nil ? nil : "\(id.uuidString).artwork"
        let audioURL = directory.appendingPathComponent(audioName)
        let artURL = artworkName.map { directory.appendingPathComponent($0) }
        do {
            try Task.checkCancellation()
            try manager.copyItem(at: downloaded.url, to: audioURL)
            if let data = metadata.artwork, let artURL { try data.write(to: artURL, options: .atomic) }
            #if os(iOS)
            for url in [audioURL, artURL].compactMap({ $0 }) {
                try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            }
            #endif
            let song = Song(id: id, filename: audioName,
                            title: metadata.resolvedTitle(filename: downloaded.suggestedName),
                            artist: metadata.resolvedArtist, album: metadata.resolvedAlbum,
                            artworkFilename: artworkName, duration: duration, importedAt: Date())
            songs.append(song)
            try Task.checkCancellation()
            try JSONEncoder().encode(songs).write(to: indexURL, options: .atomic)
            return songs
        } catch {
            try? manager.removeItem(at: audioURL)
            if let artURL { try? manager.removeItem(at: artURL) }
            if error is CancellationError { throw CancellationError() }
            throw ImportError.storage
        }
    }
}
