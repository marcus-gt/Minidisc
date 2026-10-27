import SwiftUI

struct LyricsLineView: View {
    let value: String
    let index: Int
    let currentIndex: Int?
    let isSynced: Bool
    /// While following, lines away from the current one are blurred and dimmed; while reading they
    /// are all legible, with the current one still brightest.
    let isFollowing: Bool
    let isTappable: Bool
    let onTap: () -> Void

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var blurRadius: CGFloat {
        guard isSynced, isFollowing, currentIndex != nil else { return 0 }
        switch distance {
        case 0: return 0
        case 1: return 1.5
        case 2: return 3.5
        default: return 6
        }
    }

    private var opacity: Double {
        guard isSynced, currentIndex != nil else { return 1.0 }
        guard isFollowing else { return distance == 0 ? 1.0 : 0.65 }
        switch distance {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.4
        default: return 0.25
        }
    }

    /// The current line is emphasised by shrinking the others: scaling it up instead would push its
    /// text past the right edge, where it was cut off.
    private var scale: CGFloat {
        guard isSynced, isFollowing, currentIndex != nil else { return 1.0 }
        return distance == 0 ? 1.0 : 0.95
    }

    private var lineFont: Font {
        .system(.title, weight: .bold)
    }

    var body: some View {
        Text(value)
            .font(lineFont)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: blurRadius)
            .scaleEffect(scale, anchor: .leading)
            .animation(.easeInOut(duration: 0.25), value: currentIndex)
            .animation(.easeInOut(duration: 0.25), value: isFollowing)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
    }
}
