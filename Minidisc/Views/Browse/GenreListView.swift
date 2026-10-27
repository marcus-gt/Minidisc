import SwiftUI

/// Library → Genres (#49): the library's genre tags grouped under main genres. A main genre opens
/// "All <genre>" and its styles; each opens the matching albums.
struct GenreListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: GenreListViewModel?
    @State private var filterText = ""

    /// `viewModel` is for Previews: a supplied model is loaded instead of one built from the container.
    init(viewModel: GenreListViewModel? = nil) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingStateView()
            }
        }
        .minidiscContentWidth()
        .navigationTitle("Genres")
        .toolbarTitleDisplayMode(.inline)
        .minidiscFilterable(text: $filterText, prompt: "Filter genres")
        .task {
            if let viewModel {
                if viewModel.state == .loading { await viewModel.load() }
                return
            }
            guard let library = container?.libraryService else { return }
            let model = GenreListViewModel(library: library)
            viewModel = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: GenreListViewModel) -> some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .waitingForIndex:
            EmptyStateView(
                systemImage: "hourglass",
                title: "Still Indexing Your Library",
                subtitle: "Genres appear once maekster has indexed every album. Try again shortly."
            )
        case .failed(let error):
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Genres",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await viewModel.load() } }
            )
        case .loaded where viewModel.genres.isEmpty:
            EmptyStateView(
                systemImage: "guitars",
                title: "No Genres",
                subtitle: "None of your albums are tagged with a genre."
            )
        case .loaded:
            let genres = filtered(viewModel.genres)
            if genres.isEmpty {
                FilterNoResultsView(query: filterText)
            } else {
                List(genres) { genre in
                    NavigationLink {
                        GenreDetailView(genre: genre)
                    } label: {
                        GenreRow(title: GenreRow.title(genre.isOther ? nil : genre.name), albumCount: genre.albumCount, coverArtId: genre.coverArtId)
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
    }

    /// A main genre matches by its own name or any of its styles, so "bop" still finds Jazz.
    private func filtered(_ genres: [MainGenreSummary]) -> [MainGenreSummary] {
        LibraryFilter.filter(genres, by: filterText) { [$0.name] + $0.styles.map(\.name) }
    }
}

/// One main genre: "All <genre>", then its styles, biggest first.
struct GenreDetailView: View {
    let genre: MainGenreSummary

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AlbumCollectionView(kind: .genreGroup(name: genre.isOther ? String(localized: "Other") : genre.name, tags: genre.tags))
                } label: {
                    GenreRow(
                        title: genre.isOther ? Text("All Other Genres") : Text("All \(genre.name)"),
                        albumCount: genre.albumCount,
                        coverArtId: genre.coverArtId
                    )
                }
            }
            if !genre.styles.isEmpty {
                Section {
                    ForEach(genre.styles) { style in
                        NavigationLink {
                            AlbumCollectionView(kind: .genreGroup(name: style.name, tags: style.tags))
                        } label: {
                            GenreRow(title: GenreRow.title(style.name), albumCount: style.albumCount, coverArtId: style.coverArtId)
                        }
                    }
                } header: {
                    Text("Styles")
                }
            }
        }
        .listStyle(.plain)
        .minidiscContentWidth()
        .navigationTitle(genre.isOther ? Text("Other") : Text(verbatim: genre.name))
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct GenreRow: View {
    let title: Text
    let albumCount: Int
    let coverArtId: String?

    /// A tag spelled as in the library; `nil` stands for the localized "Other".
    static func title(_ name: String?) -> Text {
        name.map { Text(verbatim: $0) } ?? Text("Other")
    }

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            if let coverArtId {
                CoverArtCard(id: coverArtId, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.minidiscCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(albumCount) albums")
                    .font(.minidiscCellSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MinidiscSpacing.xs)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("Genres") {
    MinidiscPreview(container: .preview()) {
        NavigationStack {
            GenreListView(viewModel: GenreListViewModel(library: PreviewLibraryService()))
        }
    }
}

#Preview("Genre") {
    MinidiscPreview(container: .preview()) {
        NavigationStack {
            GenreDetailView(genre: MainGenreSummary(
                name: "Jazz", tags: ["Jazz", "Hard Bop", "Modal"], albumCount: 12, coverArtId: nil,
                styles: [
                    GenreStyleSummary(name: "Hard Bop", tags: ["Hard Bop"], albumCount: 7, coverArtId: nil),
                    GenreStyleSummary(name: "Modal", tags: ["Modal", "Modal Jazz"], albumCount: 4, coverArtId: nil)
                ]
            ))
        }
    }
}
#endif
