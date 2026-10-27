import SwiftUI
import OSLog

struct FreshReleaseDetailView: View {
    let release: AlbumRecommendation
    let providers: [ExternalReleaseProvider]

    @Environment(\.appContainer) private var container
    @State private var storeLinks: [StoreLink]?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MinidiscSpacing.l) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ExternalCoverView(url: release.coverArtURL) {
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.large)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    Text(release.title)
                        .font(.title2.bold())

                    Text(release.artistName)
                        .font(.minidiscCellTitle)
                        .foregroundStyle(.secondary)

                    if let details = detailsLine {
                        Text(verbatim: details)
                            .font(.minidiscCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                storeSection
                externalLinksSection
            }
            .padding(MinidiscSpacing.l)
        }
        .navigationTitle(release.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: release.id) {
            await loadStoreLinks()
            for provider in providers {
                if provider.buildURL(artistName: release.artistName, albumTitle: release.title) == nil {
                    Logger.integrations.warning("buildURL returned nil for provider '\(provider.name, privacy: .public)'")
                }
            }
        }
    }

    /// "16 October 2026 · Album · Live".
    private var detailsLine: String? {
        let parts = [release.releaseDate.map { Self.dateFormatter.string(from: $0) }, release.typeLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Stores (#15)

    @ViewBuilder
    private var storeSection: some View {
        if let storeLinks {
            if !storeLinks.isEmpty {
                VStack(spacing: MinidiscSpacing.s) {
                    ForEach(storeLinks) { link in
                        externalLinkButton(
                            title: link.isSearch ? Text("Search on \(link.store.name)") : Text("Open on \(link.store.name)"),
                            url: link.url
                        )
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, MinidiscSpacing.s)
        }
    }

    private func loadStoreLinks() async {
        guard let id = release.id, let container else {
            storeLinks = ReleaseStoreLinks.links(recordPages: [:], artist: release.artistName, title: release.title,
                                                 region: Locale.current.region?.identifier)
            return
        }
        let links = await container.newReleasesService.storeLinks(
            releaseGroupID: id, artist: release.artistName, title: release.title,
            region: Locale.current.region?.identifier
        )
        guard !Task.isCancelled else { return }
        storeLinks = links
    }

    // MARK: - Other links

    @ViewBuilder
    private var externalLinksSection: some View {
        VStack(spacing: MinidiscSpacing.s) {
            ForEach(providers) { provider in
                if let url = provider.buildURL(artistName: release.artistName, albumTitle: release.title) {
                    externalLinkButton(title: Text("View on \(provider.name)"), url: url)
                }
            }
            if let id = release.id, let url = URL(string: "https://musicbrainz.org/release-group/\(id)") {
                externalLinkButton(title: Text("View on MusicBrainz"), url: url)
            }
        }
    }

    private func externalLinkButton(title: Text, url: URL) -> some View {
        Button {
            ExternalLinkOpener.open(url)
        } label: {
            HStack {
                title
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
            }
            .font(.minidiscCellTitle)
            .padding(MinidiscSpacing.m)
            .frame(maxWidth: .infinity)
            .background(Color.minidiscAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard, style: .continuous))
            .foregroundStyle(Color.minidiscAccent)
        }
        .buttonStyle(.plain)
    }
}
