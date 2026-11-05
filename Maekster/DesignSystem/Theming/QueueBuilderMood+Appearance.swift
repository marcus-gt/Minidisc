import SwiftUI

/// A Queue Builder mood's symbol and colour, for Wrapped and Song Path.
extension QueueBuilderMood {
    var wrappedSymbol: String {
        switch self {
        case .happy: "sun.max.fill"
        case .sad: "cloud.rain.fill"
        case .relaxed: "leaf.fill"
        case .aggressive: "flame.fill"
        case .party: "party.popper.fill"
        case .danceable: "figure.dance"
        }
    }

    var wrappedColor: Color {
        switch self {
        case .happy: .yellow
        case .sad: .blue
        case .relaxed: .green
        case .aggressive: .red
        case .party: .pink
        case .danceable: .purple
        }
    }
}
