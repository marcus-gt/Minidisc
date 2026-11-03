import SwiftUI

extension EnvironmentValues {
    /// The lyrics' text colour: white on the player's artwork background (the default), the normal
    /// text colour where lyrics sit on a plain surface (the Mac side panel).
    @Entry var maeksterLyricsColor: Color = .white
    /// The lyrics' line font: large in the player, smaller in a narrow panel.
    @Entry var maeksterLyricsFont: Font = .system(.title, weight: .bold)
}
