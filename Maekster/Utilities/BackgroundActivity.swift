import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

/// Requests a limited background grace period. Operations must still tolerate suspension
/// and persist progress before the assertion expires.
///
/// macOS doesn't suspend apps in the background; there the assertion only keeps App Nap
/// from throttling the operation.
nonisolated enum BackgroundActivity {

    #if os(iOS)
    @MainActor
    private final class Assertion {
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        private var ended = false

        func begin(name: String) {
            identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                Logger.boot.warning("[BACKGROUND] '\(name, privacy: .public)' ran out of time — suspending")
                self?.end()
            }
        }

        func end() {
            guard !ended else { return }
            ended = true
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
    #else
    @MainActor
    private final class Assertion {
        private var activity: NSObjectProtocol?

        func begin(name: String) {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: name
            )
        }

        func end() {
            guard let activity else { return }
            self.activity = nil
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
    #endif

    static func run<T: Sendable>(_ name: String, operation: @Sendable () async -> T) async -> T {
        let assertion = await MainActor.run {
            let assertion = Assertion()
            assertion.begin(name: name)
            return assertion
        }

        return await withTaskCancellationHandler {
            let result = await operation()
            await assertion.end()
            return result
        } onCancel: {
            Task { @MainActor in
                assertion.end()
            }
        }
    }
}
