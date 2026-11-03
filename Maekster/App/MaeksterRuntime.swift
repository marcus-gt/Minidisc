import Foundation

/// UI and headless audio intents must share one initialization and one playback engine.
@MainActor
final class MaeksterRuntime {
    static let shared = MaeksterRuntime()
    let diagnostics = PlaybackDiagnostics()
    private var initialization: Task<AppContainer, Error>?
    private let load: (@MainActor () async throws -> AppContainer)?
    /// The container once it's built, without starting it. Quitting on macOS uses this so it
    /// never boots the service graph just to save a session that doesn't exist.
    private(set) var readyContainer: AppContainer?

    init(load: (@MainActor () async throws -> AppContainer)? = nil) {
        self.load = load
    }

    func container() async throws -> AppContainer {
        if let initialization { return try await initialization.value }
        let task = Task {
            if let load { return try await load() }
            return try await MaeksterApp.makeContainer(diagnostics: diagnostics)
        }
        initialization = task
        do {
            let container = try await task.value
            readyContainer = container
            return container
        } catch {
            initialization = nil
            throw error
        }
    }
}
