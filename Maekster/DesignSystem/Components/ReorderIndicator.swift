import SwiftUI

/// The host owns reordering and haptics; isActive only changes the grip appearance.
struct ReorderIndicator: View {
    var isActive: Bool = false

    @Environment(\.maeksterPlayingAccent) private var playingAccent

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.maeksterCaption)
            .foregroundStyle(isActive ? playingAccent : Color.secondary)
            .accessibilityLabel("Reorder")
    }
}

#Preview("Light") {
    HStack(spacing: MaeksterSpacing.l) {
        ReorderIndicator()
        ReorderIndicator(isActive: true)
    }
    .padding()
}

#Preview("Dark") {
    HStack(spacing: MaeksterSpacing.l) {
        ReorderIndicator()
        ReorderIndicator(isActive: true)
    }
    .padding()
    .preferredColorScheme(.dark)
}
