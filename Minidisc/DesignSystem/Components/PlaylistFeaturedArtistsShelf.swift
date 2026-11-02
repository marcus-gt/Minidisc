import SwiftUI

struct PlaylistFeaturedArtistsShelf: View {
    let artists: [FeaturedArtist]
    let onSelect: (FeaturedArtist) -> Void

    var body: some View {
        MaeksterShelf {
            MaeksterCarouselHeader("Featured Artists", showsChevron: false)
                .accessibilityAddTraits(.isHeader)
        } content: {
            ForEach(artists) { artist in
                Button {
                    onSelect(artist)
                } label: {
                    ArtistPortraitCell(name: artist.name, size: MaeksterCarouselMetrics.artistArtwork) {
                        FeaturedArtistAvatar(artist: artist, size: MaeksterCarouselMetrics.artistArtwork)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playlist.featured.artist.\(artist.id)")
            }
        }
        .padding(.top, MaeksterSpacing.m)
    }
}
