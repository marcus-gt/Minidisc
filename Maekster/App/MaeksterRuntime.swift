import Foundation

/// UI and headless audio intents must share one initialization and one playback engine.
@MainActor
final class MaeksterRuntime {
    static let shared = MaeksterRuntime()
    let diagnostics = PlaybackDiagnostics()
    private var initialization: Task<AppContainer, Error>?
    private let load: (@MainActor () async throws -> AppContainer)?

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
            return try await task.value
        } catch {
            initialization = nil
            throw error
        }
    }
}
