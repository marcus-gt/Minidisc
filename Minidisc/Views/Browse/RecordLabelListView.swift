import SwiftUI

/// Every record label in the library, opened from Library → Labels. Each row opens the label's albums.
struct RecordLabelListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: RecordLabelListViewModel?
    @State private var filterText = ""

    /// `viewModel` is for Previews: a supplied model is loaded instead of one built from the container.
    init(viewModel: RecordLabelListViewModel? = nil) {
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
        .navigationTitle("Labels")
        .toolbarTitleDisplayMode(.inline)
        .minidiscFilterable(text: $filterText, prompt: "Filter labels")
        .task {
            if let viewModel {
                if viewModel.state == .loading { await viewModel.load() }
                return
            }
            guard let library = container?.libraryService else { return }
            let model = RecordLabelListViewModel(library: library)
            viewModel = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: RecordLabelListViewModel) -> some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .waitingForIndex:
            EmptyStateView(
                systemImage: "hourglass",
                title: "Still Indexing Your Library",
                subtitle: "Labels appear once maekster has indexed every album. Try again shortly."
            )
        case .failed(let error):
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Labels",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await viewModel.load() } }
            )
        case .loaded where viewModel.labels.isEmpty:
            EmptyStateView(
                systemImage: "building.2",
                title: "No Labels",
                subtitle: "None of your albums are tagged with a record label."
            )
        case .loaded:
            let labels = LibraryFilter.filter(viewModel.labels, by: filterText) { [$0.name] }
            if labels.isEmpty {
                FilterNoResultsView(query: filterText)
            } else {
                labelList(labels, viewModel: viewModel)
            }
        }
    }

    private func labelList(_ labels: [RecordLabelSummary], viewModel: RecordLabelListViewModel) -> some View {
        AlphabetIndexedContent(entries: labels.map { AlphabetScrollEntry(id: $0.id, name: $0.name) }) {
            List(labels) { label in
                NavigationLink {
                    AlbumCollectionView(kind: .recordLabel(label.name))
                } label: {
                    RecordLabelRow(label: label)
                }
                .id(label.id)
            }
            .listStyle(.plain)
            .refreshable { await viewModel.load() }
        }
    }
}

private struct RecordLabelRow: View {
    let label: RecordLabelSummary

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            if let coverArtId = label.coverArtId {
                CoverArtCard(id: coverArtId, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label.name)
                    .font(.minidiscCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(label.albumCount) albums")
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
#Preview {
    MinidiscPreview(container: .preview()) {
        NavigationStack {
            RecordLabelListView(viewModel: RecordLabelListViewModel(library: PreviewLibraryService()))
        }
    }
}
#endif
