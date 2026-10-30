import OSLog
import SwiftUI

/// A mood on Discover; tapping it starts the mood's radio (#60).
struct MoodCard: View {
    let mood: Mood

    @Environment(\.appContainer) private var container
    @State private var isStarting = false

    private let cardSize: CGFloat = 140

    var body: some View {
        Button {
            guard let container, !isStarting else { return }
            isStarting = true
            HapticFeedback.medium.trigger()
            Task {
                await MoodRadio.play(mood, container: container)
                isStarting = false
            }
        } label: {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                MoodArtwork(mood: mood)
                    .frame(width: cardSize, height: cardSize)
                    .overlay(alignment: .bottomTrailing) {
                        Group {
                            if isStarting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.minidiscCaption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(MinidiscSpacing.s)
                    }
                    .minidiscCoverStyle()
                CoverCardMetadata(title: String(localized: mood.title), subtitle: String(localized: "Mood radio"))
            }
            .frame(width: cardSize, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mood-card-\(mood.rawValue)")
        .accessibilityLabel(Text("\(String(localized: mood.title)) radio"))
        .accessibilityHint(Text("Plays songs that fit the mood"))
    }
}

/// Starts a mood's radio from the app (#60): the mood's best matches, then similar songs.
@MainActor
enum MoodRadio {
    static func play(_ mood: Mood, container: AppContainer) async {
        do {
            let radio = try await container.moodRadioService.radio(for: mood)
            guard !radio.tracks.isEmpty else {
                container.toastService.show(String(localized: "No songs in your library fit this mood yet."))
                return
            }
            try await container.playerService.playBuiltQueue(
                RadioQueue.initialTracks(radio.tracks),
                refill: RadioQueue.refill(after: radio.tracks, seedIDs: radio.seedIDs, library: container.libraryService)
            )
        } catch is CancellationError {
            return
        } catch {
            Logger.moodPlaylists.error("[MOOD] radio failed: \(error, privacy: .public)")
            container.toastService.showError(String(localized: "Couldn't start the mood radio."))
        }
    }
}
