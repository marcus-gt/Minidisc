import SwiftUI

struct WrappedTopAlbumsSection: View {
    let albums: [TopAlbumEntry]

    private let columns = [
        GridItem(.flexible(), spacing: MaeksterSpacing.m),
        GridItem(.flexible(), spacing: MaeksterSpacing.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            Text("Top Albums")
                .font(.maeksterSectionTitle)
            if albums.isEmpty {
                emptyLabel("No album data for this period.")
            } else {
                LazyVGrid(columns: columns, spacing: MaeksterSpacing.m) {
                    ForEach(albums.prefix(6)) { album in
                        // An album only in the ListenBrainz history isn't on the server to open (#16).
                        if WrappedIDs.isLibraryID(album.albumId) {
                            NavigationLink {
                                AlbumDetailView(albumId: album.albumId, albumName: album.title, coverArtId: album.albumId)
                            } label: {
                                albumCard(album)
                            }
                            .buttonStyle(.plain)
                        } else {
                            albumCard(album)
                        }
                    }
                }
            }
        }
    }

    private func albumCard(_ album: TopAlbumEntry) -> some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        CoverArtView(id: album.albumId, size: 220, tier: .hero)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard, style: .continuous))
                    .maeksterCoverStyle(cornerRadius: MaeksterCornerRadius.standard)
                rankBadge(album.rank)
                    .padding(MaeksterSpacing.xs)
            }
            CoverCardMetadata(title: album.title, subtitle: album.artistName)
        }
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return WrappedYearPalette.medalGold
        case 2: return WrappedYearPalette.medalSilver
        case 3: return WrappedYearPalette.medalBronze
        default: return MaeksterColors.accent
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        let isMedal = rank <= 3
        return Text("#\(rank)")
            .font(.maeksterCaption2)
            .fontWeight(.bold)
            .foregroundStyle(isMedal ? Color.black : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if isMedal {
                    Capsule().fill(medalColor(for: rank))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }

    private func emptyLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.maeksterCaption)
            .foregroundStyle(.secondary)
    }
}
