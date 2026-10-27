import SwiftUI

/// The current lyric line on the player screen, between the track info and the scrubber (#36).
/// Only time-synced lyrics have a current line, so nothing is shown for plain ones. Tapping opens
/// the full lyrics.
struct CurrentLyricLineView: View {
    @Bindable var viewModel: LyricsViewModel
    let contentColor: Color
    let onTap: () -> Void

    var body: some View {
        Group {
            if let line = viewModel.currentLine {
                Text(verbatim: line)
                    .font(.minidiscCellTitle)
                    .foregroundStyle(contentColor.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                    .id(line)
                    .transition(.opacity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .accessibilityLabel(Text("Current lyric line"))
                    .accessibilityValue(Text(verbatim: line))
                    .accessibilityHint(Text("Shows all lyrics"))
                    .accessibilityAddTraits(.isButton)
            } else {
                Color.clear
            }
        }
        // A fixed height keeps the controls below from moving as the lines change.
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.2), value: viewModel.currentLine)
        .onAppear { viewModel.setLineVisible(true) }
        .onDisappear { viewModel.setLineVisible(false) }
        .onChange(of: viewModel.isPlaying) { _, _ in viewModel.reconcileTracking() }
    }
}
