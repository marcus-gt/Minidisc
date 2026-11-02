import SwiftUI

struct FreshReleasesCard: View {
    private let cellWidth: CGFloat = 140

    let releases: [AlbumRecommendation]
    let isLoading: Bool
    let onSeeAll: () -> Void
    var zoomNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            freshReleasesHeader

            if isLoading {
                skeletonScroll
            } else if !releases.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: MaeksterSpacing.s) {
                        ForEach(releases, id: \.self) { release in
                            FreshReleaseAlbumCell(
                                release: release,
                                zoomSourceId: release.id ?? "\(release.artistName)-\(release.title)",
                                zoomNamespace: zoomNamespace
                            )
                            .frame(width: cellWidth)
                        }
                        FreshReleasesSeeAllCell(onSeeAll: onSeeAll)
                            .frame(width: cellWidth)
                    }
                    .padding(.horizontal, MaeksterSpacing.m)
                }
            } else {
                emptyStatePlaceholder(
                    icon: "music.note.list",
                    message: "No new releases from artists in your library this month."
                )
            }
        }
    }

    @ViewBuilder
    private var freshReleasesHeader: some View {
        if releases.isEmpty {
            MaeksterCarouselHeader(
                "Fresh Releases",
                showsChevron: false,
                horizontalPadding: MaeksterSpacing.m
            )
            .accessibilityAddTraits(.isHeader)
        } else {
            Button(action: onSeeAll) {
                MaeksterCarouselHeader(
                    "Fresh Releases",
                    showsChevron: true,
                    horizontalPadding: MaeksterSpacing.m
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fresh Releases")
            .accessibilityHint("See all")
        }
    }

    private func emptyStatePlaceholder(icon: String, message: LocalizedStringKey) -> some View {
        VStack(spacing: MaeksterSpacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.maeksterCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 168)
        .padding(.horizontal, MaeksterSpacing.m)
    }

    private var skeletonScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: MaeksterSpacing.s) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
                        SkeletonBlock(width: 140, height: 140, cornerRadius: MaeksterCornerRadius.standard)
                        SkeletonBlock(width: 110, height: 12)
                        SkeletonBlock(width: 80, height: 10)
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, MaeksterSpacing.m)
        }
        .allowsHitTesting(false)
    }
}

private struct FreshReleasesSeeAllCell: View {
    let onSeeAll: () -> Void

    var body: some View {
        Button(action: onSeeAll) {
            VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard, style: .continuous)
                                .fill(Color.maeksterAccent.opacity(0.08))
                            Image(systemName: "chevron.forward")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.maeksterAccent)
                                .frame(width: 44, height: 44)
                        }
                    }
                Text("Past 90 days")
                    .font(.maeksterCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all")
        .accessibilityHint("Past 90 days")
    }
}

// MARK: - Cell

struct FreshReleaseAlbumCell: View {
    let release: AlbumRecommendation
    var zoomSourceId: String? = nil
    var zoomNamespace: Namespace.ID? = nil

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        NavigationLink(value: release) {
            cellContent
        }
        .buttonStyle(.plain)
        .maeksterMatchedTransitionSource(id: zoomSourceId, in: zoomNamespace)
    }

    private var cellContent: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ExternalCoverView(url: release.coverArtURL) {
                        Color.secondary.opacity(0.2)
                    }
                }
                .maeksterCoverStyle()

            CoverCardMetadata(
                title: release.title,
                subtitle: release.artistName,
                detail: release.releaseDate.map {
                    Self.relativeFormatter.localizedString(for: $0, relativeTo: Date())
                }
            )
        }
    }
}
