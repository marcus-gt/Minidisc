import SwiftSonic
import SwiftUI

private enum QueueBuilderMetrics {
    /// Wide enough for "Contemporary Jazz (589)" at the default text size.
    static let columnWidth: CGFloat = 188
    /// About six pills before the column scrolls.
    static let columnListHeight: CGFloat = 268
}

/// Pick genres (main genres or their sub-genres) and decades, choose a length, and build a queue (#17).
struct QueueBuilderView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: QueueBuilderViewModel?

    init() {}

    #if DEBUG
    /// Previews pass a view model fed by sample data instead of the container's service.
    init(previewModel: QueueBuilderViewModel) {
        _viewModel = State(initialValue: previewModel)
    }
    #endif

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Queue Builder")
        .navigationBarTitleDisplayModeInline()
        .task {
            if viewModel == nil, let container {
                viewModel = QueueBuilderViewModel(
                    service: container.queueBuilderService,
                    playerService: container.playerService,
                    toastService: container.toastService
                )
            }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: QueueBuilderViewModel) -> some View {
        switch vm.phase {
        case .loading:
            LoadingStateView(message: "Reading your library…")
        case .failed(let message):
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Genres",
                subtitle: "\(message)",
                action: .init(label: "Try Again") { Task { await vm.load() } }
            )
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: MinidiscSpacing.xxl) {
                    genreSection(vm)
                    decadeSection(vm)
                    lengthSection(vm)
                    buildSection(vm)
                }
                .padding(.top, MinidiscSpacing.m)
                .padding(.bottom, MinidiscSpacing.miniPlayerBottomMargin)
            }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Genres

    private func genreSection(_ vm: QueueBuilderViewModel) -> some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            header("Genres", isClearable: vm.selection.hasGenre) { vm.clearGenres() }
            TextField("Filter genres", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal, MinidiscSpacing.l)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: MinidiscSpacing.s) {
                    ForEach(vm.visibleColumns) { column in
                        GenreColumn(column: column, viewModel: vm)
                    }
                }
                .padding(.horizontal, MinidiscSpacing.l)
            }
            hint(vm.selection.hasGenre
                 ? "Songs with any picked genre are included. Tap a column title to pick the whole genre."
                 : "No genre picked: every genre is included. Tap a column title to pick the whole genre.")
        }
    }

    // MARK: - Decades

    private func decadeSection(_ vm: QueueBuilderViewModel) -> some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            header("Decades", isClearable: !vm.selection.decades.isEmpty) { vm.clearDecades() }
            MetadataChipFlow(spacing: MinidiscSpacing.s, centersRows: false) {
                ForEach(vm.decades, id: \.self) { decade in
                    SelectablePill(
                        title: "\(String(decade))s",
                        count: vm.decadeCount(decade),
                        isSelected: vm.selection.decades.contains(decade)
                    ) {
                        vm.toggle(decade: decade)
                    }
                }
            }
            .padding(.horizontal, MinidiscSpacing.l)
            hint(vm.selection.decades.isEmpty
                 ? "No decade picked: every year is included. Uses each album's original release year when known."
                 : "Songs from any picked decade are included, by each album's original release year when known.")
        }
    }

    // MARK: - Length and build

    private func lengthSection(_ vm: QueueBuilderViewModel) -> some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            SectionHeader(title: "Length")
            HStack(spacing: MinidiscSpacing.m) {
                Slider(
                    value: $vm.length,
                    in: QueueBuilderViewModel.lengthRange,
                    step: QueueBuilderViewModel.lengthStep
                )
                .accessibilityLabel("Queue length")
                .accessibilityValue(Text("\(Int(vm.length)) songs"))
                Text("\(Int(vm.length)) songs")
                    .font(.minidiscMetadata)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, MinidiscSpacing.l)
        }
    }

    private func buildSection(_ vm: QueueBuilderViewModel) -> some View {
        VStack(spacing: MinidiscSpacing.s) {
            PlayButton(
                action: { Task { await vm.build() } },
                label: vm.isBuilding ? "Building…" : "Build Queue",
                systemImage: "play.fill",
                isDisabled: !vm.canBuild
            )
            Group {
                if let count = vm.matchCount {
                    Text("^[\(count) matching song](inflect: true)")
                } else {
                    Text("Counts are approximate until your library has finished indexing.")
                }
            }
            .font(.minidiscCaption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MinidiscSpacing.l)
    }

    // MARK: - Pieces

    private func header(_ title: LocalizedStringKey, isClearable: Bool, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.minidiscSectionTitle)
            Spacer()
            if isClearable {
                Button("Clear", action: clear)
                    .font(.minidiscCellSubtitle)
            }
        }
        .padding(.horizontal, MinidiscSpacing.l)
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.minidiscCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, MinidiscSpacing.l)
    }
}

/// One main genre: its title picks the whole genre, its sub-genres scroll vertically below.
private struct GenreColumn: View {
    let column: QueueBuilderIndex.Column
    let viewModel: QueueBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            SelectablePill(
                title: column.name,
                count: column.songCount,
                isSelected: viewModel.isSelected(main: column.id),
                isProminent: true
            ) {
                viewModel.toggle(main: column.id)
            }
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                    ForEach(column.pills) { pill in
                        SelectablePill(
                            title: pill.name,
                            count: pill.songCount,
                            isSelected: viewModel.isSelected(pill: pill.id, in: column.id)
                        ) {
                            viewModel.toggle(pill: pill.id, in: column.id)
                        }
                    }
                }
            }
            .frame(height: QueueBuilderMetrics.columnListHeight)
        }
        .padding(MinidiscSpacing.s)
        .frame(width: QueueBuilderMetrics.columnWidth, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.large))
    }
}

/// A tappable pill showing a name and, when known, its song count in brackets.
private struct SelectablePill: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.light.trigger()
            action()
        } label: {
            HStack(spacing: MinidiscSpacing.xs) {
                Text(verbatim: title)
                    .font(isProminent ? .minidiscCellTitle : .minidiscCellSubtitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let count {
                    Text(verbatim: "(\(count))")
                        .font(.minidiscMetadata)
                        .foregroundStyle(isSelected ? Color.minidiscAccentText.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, MinidiscSpacing.m)
            .padding(.vertical, MinidiscSpacing.s)
            .frame(maxWidth: isProminent ? .infinity : nil, alignment: .leading)
            .foregroundStyle(isSelected ? Color.minidiscAccentText : .primary)
            .background(
                isSelected ? Color.minidiscAccent : Color.secondary.opacity(0.14),
                in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Discover entry point for the Queue Builder.
struct QueueBuilderCard: View {
    var body: some View {
        NavigationLink {
            QueueBuilderView()
        } label: {
            HStack(spacing: MinidiscSpacing.m) {
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    Label("Queue Builder", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Build Your Own Mix")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick genres and decades")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(MinidiscSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.05, green: 0.20, blue: 0.40),
                                                 Color(red: 0.05, green: 0.50, blue: 0.55)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MinidiscSpacing.l)
        .accessibilityIdentifier("discover.queueBuilder")
    }
}

#if DEBUG
private nonisolated struct PreviewQueueBuilderSource: QueueBuilderLibrarySource {
    func queueBuilderStamp() async throws -> String? { "preview" }
    func queueBuilderTracks() async throws -> [QueueBuilderTrack]? {
        let shapes: [([String], Int, Int)] = [
            (["Modal"], 1959, 40), (["Fusion", "Contemporary Jazz"], 1976, 55), (["Contemporary Jazz"], 2004, 80),
            (["Hard Bop"], 1962, 35), (["Techno"], 1994, 120), (["House", "Deep House"], 2001, 70),
            (["IDM", "Ambient"], 1997, 45), (["Hip-Hop", "Conscious"], 1993, 60), (["Trip Hop"], 1995, 30),
            (["Alternative Rock"], 1991, 65), (["Punk Rock"], 1978, 25), (["Soul"], 1968, 40), (["Norway"], 2015, 5),
        ]
        var tracks: [QueueBuilderTrack] = []
        for (genres, year, count) in shapes {
            for index in 0..<count {
                let id = "\(genres[0])-\(index)"
                let song = try JSONDecoder().decode(Song.self, from: Data("{\"id\":\"\(id)\",\"title\":\"\(id)\",\"isDir\":false}".utf8))
                tracks.append(QueueBuilderTrack(song: song, genres: genres, year: year + index % 8))
            }
        }
        return tracks
    }
}

#Preview("Queue Builder") {
    let container = AppContainer.preview()
    let model = QueueBuilderViewModel(
        service: QueueBuilderService(source: PreviewQueueBuilderSource(), library: container.libraryService),
        playerService: container.playerService,
        toastService: container.toastService
    )
    return MinidiscPreview(container: container) {
        NavigationStack { QueueBuilderView(previewModel: model) }
    }
}

#Preview("Queue Builder · picked") {
    let container = AppContainer.preview()
    let model = QueueBuilderViewModel(
        service: QueueBuilderService(source: PreviewQueueBuilderSource(), library: container.libraryService),
        playerService: container.playerService,
        toastService: container.toastService
    )
    model.selection = QueueBuilderSelection(
        mains: ["Jazz"],
        tags: [GenreTaxonomy.discogs.resolve("Techno").key, GenreTaxonomy.discogs.resolve("IDM").key],
        decades: [1990, 2000]
    )
    return MinidiscPreview(container: container) {
        NavigationStack { QueueBuilderView(previewModel: model) }
    }
}

#Preview("Discover card") {
    NavigationStack { QueueBuilderCard() }
}
#endif
