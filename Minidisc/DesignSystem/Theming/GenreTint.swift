import SwiftUI

/// Fixed colours that tell the Queue Builder's main genres apart (#17). Sub-genres use their main
/// genre's tint. Every tint keeps white text at WCAG AA (≥ 4.5:1) when a pill is picked; see
/// MinidiscColors.md. "Other", decades and moods stay neutral, so colour always means genre.
nonisolated enum GenreTint {
    static func color(for mainGenre: String) -> Color? {
        tints[mainGenre].map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    private static let tints: [String: (red: Double, green: Double, blue: Double)] = [
        "Electronic": rgb(0x4B5BD6),
        "Rock": rgb(0xC0392B),
        "Jazz": rgb(0xA6611C),
        "Hip Hop": rgb(0x7D3C98),
        "Funk / Soul": rgb(0xB03A70),
        "Pop": rgb(0xC2185B),
        "Folk, World, & Country": rgb(0x5E6E22),
        "Blues": rgb(0x1F5FA8),
        "Reggae": rgb(0x2E7D32),
        "Classical": rgb(0x566573),
        "Latin": rgb(0x00796B),
        "Stage & Screen": rgb(0x455A64),
        "Non-Music": rgb(0x6B6B6B),
        "Brass & Military": rgb(0x7B5E52),
        "Children's": rgb(0x00737E),
    ]

    private static func rgb(_ hex: Int) -> (red: Double, green: Double, blue: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// Pill colouring shared by the Discover card and the full page. With a tint: a faint tinted fill
/// and outline, solid tint when picked. Without one: the neutral fill, accent when picked.
struct PillAppearance {
    let tint: Color?
    let isSelected: Bool

    var foreground: Color { isSelected ? .minidiscAccentText : .primary }

    var fill: Color {
        if let tint { return isSelected ? tint : tint.opacity(0.16) }
        return isSelected ? .minidiscAccent : Color.secondary.opacity(0.14)
    }

    /// Outline only for unpicked tinted pills, so the genre reads even when nothing is picked.
    var stroke: Color {
        guard let tint, !isSelected else { return .clear }
        return tint.opacity(0.55)
    }
}
