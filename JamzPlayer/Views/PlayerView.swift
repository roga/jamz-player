import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let song = player.currentSong {
                    VStack(spacing: 20) {
                        ArtworkView(url: player.repository.artworkURL(for: song))
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                            .shadow(color: .black.opacity(0.35), radius: 25, y: 16)
                            .frame(maxWidth: 280).padding(.top, 12)
                        VStack(spacing: 8) {
                            Text(song.title).font(.title.bold()).multilineTextAlignment(.center)
                            Text(song.artist).font(.title3).foregroundStyle(.secondary)
                            Text(song.album).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                        VStack(spacing: 8) {
                            Slider(value: Binding(get: { isSeeking ? seekPosition : player.position },
                                                  set: { seekPosition = $0 }),
                                   in: 0...max(1, player.duration)) { editing in
                                if editing { seekPosition = player.position; isSeeking = true }
                                else { player.seek(to: seekPosition); isSeeking = false }
                            }.accessibilityLabel("播放進度")
                            HStack {
                                Text(PlaybackTime.string(isSeeking ? seekPosition : player.position))
                                Spacer()
                                Text(PlaybackTime.string(player.duration))
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 40) {
                            Button("上一首", systemImage: "backward.end.fill", action: player.previous)
                                .font(.title).frame(minWidth: 44, minHeight: 44)
                            Button(player.isPlaying ? "暫停" : "播放", systemImage: player.isPlaying ? "pause.fill" : "play.fill", action: player.toggle)
                                .font(.system(size: 30, weight: .bold))
                                .frame(width: 84, height: 84).background(JamzTheme.accent, in: Circle()).foregroundStyle(.black)
                            Button("下一首", systemImage: "forward.end.fill", action: player.next)
                                .font(.title).frame(minWidth: 44, minHeight: 44)
                        }.labelStyle(.iconOnly).buttonStyle(.plain)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { repeatMenu; sleepMenu }
                            VStack(spacing: 10) { repeatMenu; sleepMenu }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 32)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
            .background { JamzBackground() }
            .navigationTitle("正在播放")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("收合", systemImage: "chevron.down") { dismiss() }
                }
            }
            .onChange(of: player.currentSong?.id) { _, _ in isSeeking = false }
            .alert("無法播放音樂", isPresented: Binding(get: { player.errorMessage != nil },
                                                    set: { if !$0 { player.errorMessage = nil } })) {
                Button("好") { player.errorMessage = nil }
            } message: { Text(player.errorMessage ?? "") }
        }
    }

    private var repeatMenu: some View {
        Menu {
            Picker("循環模式", selection: $player.repeatMode) {
                ForEach(RepeatMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
        } label: {
            Label(player.repeatMode.title, systemImage: player.repeatMode.symbol)
                .font(.subheadline.weight(.medium)).padding(12)
        }
        .foregroundStyle(player.repeatMode == .off ? Color.secondary : JamzTheme.accent)
        .background(JamzTheme.surface, in: Capsule())
    }

    private var sleepMenu: some View {
        Menu {
            ForEach(SleepTimerState.presets, id: \.self) { minutes in
                Button("\(minutes) 分鐘後停止") { player.setSleepTimer(minutes: minutes) }
            }
            if player.sleepRemaining != nil {
                Divider()
                Button("取消定時器", role: .destructive, action: player.cancelSleepTimer)
            }
        } label: {
            Label(player.sleepRemaining.map { "\(PlaybackTime.string(ceil($0))) 後停止" } ?? "睡眠定時器",
                  systemImage: "moon.zzz")
                .font(.subheadline.weight(.medium)).monospacedDigit().padding(12)
        }
        .foregroundStyle(player.sleepRemaining == nil ? Color.secondary : JamzTheme.accent)
        .background(JamzTheme.surface, in: Capsule())
    }
}
