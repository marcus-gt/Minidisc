import OSLog
import SwiftUI

/// Plays a period's Wrapped radio (#69): the library tracks played in that period, shuffled with the
/// most played ones tending to come first. When those run out it carries on with similar songs
/// (Navidrome's, so AudioMuse when the server has it) around the period's top tracks.
@MainActor
enum WrappedRadio {
    static func play(_ period: WrappedPeriod, container: AppContainer) async {
        guard let serverId = container.serverState.activeServer?.id.uuidString else {
            Logger.wrapped.warning("[WRAPPED] radio: no active server")
            return
        }
        let radio = await container.wrappedDataSource.radio(for: period, serverId: serverId, calendar: .current)
        guard !radio.tracks.isEmpty else {
            container.toastService.show(String(localized: "No library tracks were played in this period."))
            return
        }
        do {
            try await container.playerService.playBuiltQueue(
                RadioQueue.initialTracks(radio.tracks),
                refill: RadioQueue.refill(after: radio.tracks, seedIDs: radio.seedIDs, library: container.libraryService)
            )
        } catch {
            Logger.wrapped.error("[WRAPPED] radio failed: \(error, privacy: .public)")
            container.toastService.showError(String(localized: "Couldn't start the Wrapped radio."))
        }
    }
}

/// The large card at the bottom of a recap that starts the period's radio.
struct WrappedRadioCard: View {
    let period: WrappedPeriod
    let firstTrack: TopTrackEntry?
    let lastTrack: TopTrackEntry?

    @Environment(\.appContainer) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isStarting = false

    private var year: Int {
        switch period {
        case .month(let year, _), .year(let year): year
        case .allTime: Calendar.current.component(.year, from: Date())
        }
    }

    var body: some View {
        Button {
            guard let container, !isStarting else { return }
            isStarting = true
            Task {
                await WrappedRadio.play(period, container: container)
                isStarting = false
            }
        } label: {
            MeshGradientBackground(palette: WrappedYearPalette.colors(for: year), animated: !reduceMotion)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .overlay { overlayContent }
                .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Play Wrapped Radio"))
        .accessibilityValue(Text(verbatim: period.displayName))
        .accessibilityAddTraits(.isButton)
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
            HStack {
                Label("Wrapped Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if isStarting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            Text(verbatim: period.displayName)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            subtitle
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
        }
        .padding(MinidiscSpacing.l)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            Text("Started with \(first.title) · Ended with \(last.title)")
        } else {
            Text("What you played most, shuffled, then similar songs.")
        }
    }
}
