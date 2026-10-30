import SwiftUI

/// A year in the Wrapped carousel and grid (#69). Opens the year's recap; the story plays from the
/// corner once it is unlocked, and the context menu starts the year's radio.
struct WrappedYearTile: View {
    let year: Int

    @Environment(\.appContainer) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStoryPlayer = false

    private var storyAvailable: Bool { WrappedStoryAvailability.isStoryAvailable(forYear: year) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink {
                WrappedView(initialPeriod: .year(year))
            } label: {
                MeshGradientBackground(palette: WrappedYearPalette.colors(for: year), animated: !reduceMotion)
                    .frame(width: 140, height: 140)
                    .overlay { cardOverlay }
                    .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
                    .drawingGroup()
            }
            .buttonStyle(.plain)

            if storyAvailable {
                Button {
                    showStoryPlayer = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(MinidiscSpacing.s)
                .accessibilityLabel(Text("Play Story"))
            }
        }
        .contextMenu {
            Button("Play Wrapped Radio", systemImage: "dot.radiowaves.left.and.right") {
                guard let container else { return }
                Task { await WrappedRadio.play(.year(year), container: container) }
            }
        }
        .minidiscFullScreenCover(isPresented: $showStoryPlayer) {
            WrappedStoryPlayerView(year: year)
        }
    }

    private var cardOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            Text(verbatim: String(year))
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("Wrapped")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MinidiscSpacing.s)
    }
}

/// Years with listens, newest first: back to the first ListenBrainz listen, or only the current
/// year for plays recorded on this phone.
struct WrappedYears {
    static func years(firstYear: Int?, calendar: Calendar = .current) -> [Int] {
        let current = calendar.component(.year, from: Date())
        return Array((min(firstYear ?? current, current)...current).reversed())
    }
}
