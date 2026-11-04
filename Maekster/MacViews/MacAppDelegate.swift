import AppKit
import OSLog

/// Saves the playback session before the Mac app quits (#102), and provides the Dock menu (#107).
///
/// On iOS the background save gets time to finish. Quitting a Mac app doesn't wait for the
/// `scenePhase` save, so the queue came back at whatever the last 15-second save had stored. Here
/// quitting waits for the save, but never longer than two seconds.
final class MaeksterMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let playerService = MaeksterRuntime.shared.readyContainer?.playerService else {
            return .terminateNow
        }
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await playerService.saveSessionForBackground() }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
            Logger.session.info("App quitting — session saved")
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Play/Pause, Next and Previous when the Dock icon is right-clicked.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let state = MaeksterRuntime.shared.readyContainer?.playerState, state.currentTrack != nil else {
            return nil
        }
        let menu = NSMenu()
        menu.addItem(withTitle: state.wantsPlayback ? String(localized: "Pause") : String(localized: "Play"),
                     action: #selector(togglePlayPause), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Next Track"), action: #selector(nextTrack), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Previous Track"), action: #selector(previousTrack), keyEquivalent: "").target = self
        return menu
    }

    @objc private func togglePlayPause() {
        guard let player = MaeksterRuntime.shared.readyContainer?.playerService else { return }
        Task { await player.togglePlayPause() }
    }

    @objc private func nextTrack() {
        guard let container = MaeksterRuntime.shared.readyContainer else { return }
        Task { await container.toastService.perform { try await container.playerService.skipToNext() } }
    }

    @objc private func previousTrack() {
        guard let container = MaeksterRuntime.shared.readyContainer else { return }
        Task { await container.toastService.perform { try await container.playerService.skipToPrevious() } }
    }
}
