import SwiftUI

extension FocusedValues {
    /// The focused main window's panels (Now Playing, queue, volume), for the menu bar.
    @Entry var macPanels: MacPlayerPanels?
    /// The focused main window's navigator, for the menu bar.
    @Entry var macNavigator: MacNavigator?
}

/// The Mac menu bar: File › New Playlist, a Controls menu like the Music app's, View › Now Playing,
/// Lyrics and Queue, and Window › Mini Player.
///
/// Play/Pause has no key equivalent here: Space is handled by `MacSpacebarPlayPause`, which leaves
/// it to text fields; a menu shortcut would take it from them.
struct MacCommands: Commands {
    @FocusedValue(\.macPanels) private var panels
    @FocusedValue(\.macNavigator) private var navigator
    @Environment(\.openWindow) private var openWindow

    private var container: AppContainer? { MaeksterRuntime.shared.readyContainer }
    private var state: PlayerState? { container?.playerState }
    private var hasTrack: Bool { state?.currentTrack != nil }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Playlist") { navigator?.requestNewPlaylist() }
                .keyboardShortcut("n")
                .disabled(navigator == nil)
        }

        CommandMenu("Controls") {
            Button(state?.wantsPlayback == true ? "Pause" : "Play") {
                guard let player = container?.playerService else { return }
                Task { await player.togglePlayPause() }
            }
            .disabled(!hasTrack)
            Button("Next Track") { skip(forward: true) }
                .keyboardShortcut(.rightArrow)
                .disabled(!hasTrack)
            Button("Previous Track") { skip(forward: false) }
                .keyboardShortcut(.leftArrow)
                .disabled(!hasTrack)

            Divider()

            Button("Increase Volume") { panels?.adjustVolume(by: 0.1) }
                .keyboardShortcut(.upArrow)
                .disabled(panels == nil)
            Button("Decrease Volume") { panels?.adjustVolume(by: -0.1) }
                .keyboardShortcut(.downArrow)
                .disabled(panels == nil)

            Divider()

            Toggle("Shuffle", isOn: Binding(
                get: { state?.isShuffled == true },
                set: { _ in
                    guard let player = container?.playerService else { return }
                    Task { await player.toggleShuffle() }
                }
            ))
            .disabled(!hasTrack)
            Picker("Repeat", selection: Binding(
                get: { state?.repeatMode ?? .off },
                set: { mode in
                    guard let player = container?.playerService else { return }
                    Task { await player.setRepeatMode(mode) }
                }
            )) {
                ForEach(RepeatMode.allCases, id: \.self) { mode in
                    Text(mode.accessibilityValue).tag(mode)
                }
            }
            .disabled(!hasTrack)

            Divider()

            Button("Go to Current Song") { goToCurrentSong() }
                .keyboardShortcut("l")
                .disabled(state?.currentTrack?.albumId == nil || navigator == nil)
            Button("Smart Shuffle") {
                guard let container else { return }
                Task { await container.toastService.perform { try await container.playerService.playSmartShuffle() } }
            }
            .disabled(container == nil)
            Button("Instant Mix") {
                guard let track = state?.currentTrack else { return }
                startInstantMix(from: .song(id: track.id), using: container, startingWith: track)
            }
            .disabled(!hasTrack || state?.currentTrack?.isLocalFile == true)
        }

        CommandGroup(after: .sidebar) {
            Button("Now Playing") { panels?.showsNowPlaying.toggle() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(panels == nil || !hasTrack)
            Button("Lyrics") { panels?.toggleLyrics() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(panels == nil || !hasTrack)
            Button("Queue") { panels?.showsQueue.toggle() }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(panels == nil)
            Divider()
        }

        CommandGroup(before: .windowList) {
            Button("Mini Player") { openWindow(id: MacMiniPlayer.windowID) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
        }
    }

    private func skip(forward: Bool) {
        guard let container else { return }
        Task {
            await container.toastService.perform {
                if forward {
                    try await container.playerService.skipToNext()
                } else {
                    try await container.playerService.skipToPrevious()
                }
            }
        }
    }

    /// Opens the playing song's album, leaving Now Playing.
    private func goToCurrentSong() {
        guard let albumId = state?.currentTrack?.albumId, let navigator else { return }
        panels?.showsNowPlaying = false
        navigator.open(.album(id: albumId))
    }
}
