import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: PlayerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsPlayer = false
    @State private var editingSong: Song?
    @State private var deletingSong: Song?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if library.isMutating { ProgressView("正在更新音樂庫…") }
                    if !library.isLoaded {
                        VStack(spacing: 16) {
                            Text("正在開啟音樂庫").font(.headline)
                            Button("重新載入") { Task { await library.load() } }
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if library.songs.isEmpty {
                        emptyLibrary
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(library.songs) { song in songRow(song) }
                        }
                    }
                }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 24)
            }
            .background { JamzBackground() }
            .navigationTitle("Jamz Player")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform").foregroundStyle(JamzTheme.accent)
                        Text("JAMZ").font(.headline.weight(.black)).tracking(3)
                        Text("PLAYER").font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("Jamz Player")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("匯入音樂", systemImage: "plus") { library.showsImport = true }
                        .labelStyle(.iconOnly).font(.headline)
                        .disabled(!library.isLoaded || library.isBusy)
                        .accessibilityIdentifier("importMusic")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let song = player.currentSong { miniPlayer(song) }
            }
        }
        .task { await library.load(); player.updateQueue(library.songs) }
        .onChange(of: library.songs) { _, songs in
            player.updateQueue(songs)
            if player.currentSong == nil { showsPlayer = false }
        }
        .sheet(isPresented: $library.showsImport) {
            ImportView(isImporting: library.isImporting, progress: library.progress,
                       status: library.status, onImport: library.startImport, onCancel: library.cancelImport)
                .alert("無法匯入音樂", isPresented: libraryError) {
                    Button("好") { library.errorMessage = nil }
                } message: { Text(library.errorMessage ?? "") }
        }
        .sheet(item: $editingSong) { song in
            SongEditView(song: song) { title, artist, album in
                await library.edit(song, title: title, artist: artist, album: album)
            }
        }
        .sheet(isPresented: $showsPlayer) { PlayerView(player: player) }
        .alert("刪除歌曲？", isPresented: Binding(get: { deletingSong != nil },
                                              set: { if !$0 { deletingSong = nil } }), presenting: deletingSong) { song in
            Button("刪除", role: .destructive) {
                deletingSong = nil
                Task { await library.delete(song) }
            }
            Button("取消", role: .cancel) { deletingSong = nil }
        } message: { song in
            Text("確定要刪除「\(song.title)」嗎？將移除 App 內的音檔、封面與音樂庫紀錄，此操作無法復原。")
        }
        .alert("無法更新音樂庫", isPresented: Binding(get: { library.errorMessage != nil && !library.showsImport },
                                                  set: { if !$0 { library.errorMessage = nil } })) {
            Button("好") { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .alert("無法播放音樂", isPresented: Binding(get: { player.errorMessage != nil && !showsPlayer },
                                                set: { if !$0 { player.errorMessage = nil } })) {
            Button("好") { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(JamzTheme.accent).frame(width: 6, height: 6)
                Text("你的離線音樂空間").font(.caption.weight(.medium)).tracking(2).foregroundStyle(.secondary)
            }
            Text("音樂庫").font(.largeTitle.bold())
            Text(library.songs.isEmpty ? "收藏喜歡的聲音，留給自己的時間。" : "\(library.songs.count) 首歌曲・隨時聆聽")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 22) {
            ArtworkView(url: nil)
                .frame(width: 190, height: 190).clipShape(RoundedRectangle(cornerRadius: 28))
                .rotationEffect(.degrees(-8))
                .shadow(color: JamzTheme.accent.opacity(0.10), radius: 28, y: 12)
                .padding(.vertical, 16)
            VStack(spacing: 10) {
                Text("第一首，就從喜歡的開始").font(.title2.bold())
                Text("貼上音樂網址，下載到手機。\n沒有網路，也有自己的節奏。")
                    .font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
            }.multilineTextAlignment(.center)
            Button { library.showsImport = true } label: {
                Label("匯入第一首音樂", systemImage: "plus")
                    .font(.headline).padding(.horizontal, 24).padding(.vertical, 16)
                    .foregroundStyle(.black).background(JamzTheme.accent, in: Capsule())
            }.buttonStyle(.plain)
            Text("MP3 音檔 · HTTPS 下載 · 離線播放")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.top, 20)
    }

    private func songRow(_ song: Song) -> some View {
        let selected = player.currentSong?.id == song.id
        return Button { player.select(song, songs: library.songs) } label: {
            HStack(spacing: 14) {
                ArtworkView(url: library.repository.artworkURL(for: song))
                    .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title).font(.headline).foregroundStyle(selected ? JamzTheme.accent : .primary).lineLimit(2)
                    Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill").foregroundStyle(JamzTheme.accent)
                } else if !typeSize.isAccessibilitySize {
                    Text(PlaybackTime.string(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(selected ? JamzTheme.accent.opacity(0.08) : JamzTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(selected ? JamzTheme.accent.opacity(0.20) : .white.opacity(0.035)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(song.title)，\(song.artist)")
        .accessibilityHint("點按播放，長按編輯或刪除")
        .disabled(library.isMutating)
        .contextMenu {
            Button("編輯", systemImage: "pencil") { editingSong = song }.disabled(library.isBusy)
            Button("刪除", systemImage: "trash", role: .destructive) { deletingSong = song }.disabled(library.isBusy)
        }
    }

    private func miniPlayer(_ song: Song) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { showsPlayer = true } label: {
                    HStack(spacing: 12) {
                        ArtworkView(url: library.repository.artworkURL(for: song))
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).font(.headline).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("開啟播放器，\(song.title)").accessibilityIdentifier("openPlayer")
                Button(player.isPlaying ? "暫停" : "播放", systemImage: player.isPlaying ? "pause.fill" : "play.fill", action: player.toggle)
                    .labelStyle(.iconOnly).font(.title2).frame(width: 48, height: 48)
                    .foregroundStyle(JamzTheme.accent)
            }
            ProgressView(value: min(player.position, max(1, player.duration)), total: max(1, player.duration))
                .accessibilityHidden(true)
            if let remaining = player.sleepRemaining {
                Label("\(PlaybackTime.string(ceil(remaining))) 後停止", systemImage: "moon.zzz")
                    .font(.caption.monospacedDigit()).foregroundStyle(JamzTheme.accent)
            }
        }
        .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10)) }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private var libraryError: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
    }
}
