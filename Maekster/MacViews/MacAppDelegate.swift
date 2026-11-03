import AppKit
import OSLog

/// Saves the playback session before the Mac app quits (#102).
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
}
