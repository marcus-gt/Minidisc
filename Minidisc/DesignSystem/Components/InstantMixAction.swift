import Foundation
import OSLog

let instantMixSymbol = "sparkles"

/// Awaits playback startup. Empty mixes produce an informational toast; other failures show an error.
@MainActor
/// `title` names the seed for "Playing from" (#71); a song seed defaults to the song's title.
func runInstantMix(from seed: InstantMixSeed, using container: AppContainer?, startingWith seedTrack: DisplayableSong? = nil,
                   titled title: String? = nil) async {
    guard let container else { return }
    do {
        try await container.playerService.playInstantMix(
            from: seed, startingWith: seedTrack,
            source: .instantMix(seed: seed, title: title ?? seedTrack?.title)
        )
    } catch MinidiscError.instantMixEmpty {
        container.toastService.show(
            "No similar tracks found for an Instant Mix yet.",
            style: .info,
            duration: 4.0
        )
    } catch {
        Logger.player.error("[INSTANT-MIX] failed: \(error, privacy: .public)")
        container.toastService.showError("Couldn't start Instant Mix.")
    }
}

/// Fire-and-forget Instant Mix for menu items (the menu dismisses on tap, so there is no spam risk and no
/// need for a spinner). Persistent buttons should instead `await runInstantMix` behind their own loading state.
@MainActor
func startInstantMix(from seed: InstantMixSeed, using container: AppContainer?, startingWith seedTrack: DisplayableSong? = nil,
                     titled title: String? = nil) {
    Task { await runInstantMix(from: seed, using: container, startingWith: seedTrack, titled: title) }
}
