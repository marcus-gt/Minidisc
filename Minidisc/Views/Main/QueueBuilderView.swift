import SwiftSonic
import SwiftUI

private enum QueueBuilderMetrics {
    /// Wide enough for "Contemporary Jazz (589)" at the default text size.
    static let columnWidth: CGFloat = 188
    /// About six pills before the column scrolls.
    static let columnListHeight: CGFloat = 268
    /// Keeps the Discover card from jumping while its genres load.
    static let cardLoadingHeight: CGFloat = 96
}

/// Pick genres (main genres or their sub-genres) and decades, choose a length, and build a queue (#17).
struct QueueBuilderView: View {
    /// Shared with the Discover card, so picks made in either place show in both.
    let viewModel: QueueBuilderViewModel

    var body: some View {
        content(viewModel)
            .navigationTitle("Queue Builder")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                if !viewModel.selection.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reset") { viewModel.reset() }
                    }
                }
            }
            .task { await viewModel.load() }
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
                    if vm.isMoodAvailable { moodSection(vm) }
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

    // MARK: - Moods

    /// Only shown when AudioMuse is set up for this server; the builder works without it.
    private func moodSection(_ vm: QueueBuilderViewModel) -> some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            header("Mood", isClearable: !vm.selection.moods.isEmpty) { vm.clearMoods() }
            MetadataChipFlow(spacing: MinidiscSpacing.s, centersRows: false) {
                ForEach(QueueBuilderMood.allCases) { mood in
                    SelectablePill(
                        title: String(localized: mood.title),
                        count: nil,
                        isSelected: vm.selection.moods.contains(mood)
                    ) {
                        vm.toggle(mood: mood)
                    }
                }
            }
            .padding(.horizontal, MinidiscSpacing.l)
            hint(vm.selection.moods.isEmpty
                 ? "No mood picked: no mood ranking. Moods come from AudioMuse's analysis of each song."
                 : "The songs that match your genres and decades best for every picked mood are kept. Songs AudioMuse hasn't analysed are left out.")
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

    private var tint: Color? { GenreTint.color(for: column.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            SelectablePill(
                title: column.name,
                count: column.songCount,
                isSelected: viewModel.isSelected(main: column.id),
                isProminent: true,
                tint: tint
            ) {
                viewModel.toggle(main: column.id)
            }
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                    ForEach(column.pills) { pill in
                        SelectablePill(
                            title: pill.name,
                            count: pill.songCount,
                            isSelected: viewModel.isSelected(pill: pill.id, in: column.id),
                            tint: tint
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
        .background((tint ?? Color.secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.large))
    }
}

/// A tappable pill showing a name and, when known, its song count in brackets.
private struct SelectablePill: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    var isProminent = false
    /// The main genre's colour; nil for decades, moods and "Other".
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        let appearance = PillAppearance(tint: tint, isSelected: isSelected)
        let shape = RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard)
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
            .foregroundStyle(appearance.foreground)
            .background(appearance.fill, in: shape)
            .overlay(shape.strokeBorder(appearance.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Queue Builder on Discover: pick and play without opening the full page (#17).
/// Rows: main genres, the focused genre's sub-genres, decades, moods (with AudioMuse).
struct QueueBuilderCard: View {
    let viewModel: QueueBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            header
            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: QueueBuilderMetrics.cardLoadingHeight)
            case .failed:
                Button("Couldn't load genres. Try again") { Task { await viewModel.load() } }
                    .font(.minidiscCellSubtitle)
                    .padding(.horizontal, MinidiscSpacing.l)
            case .ready:
                rows
            }
        }
        .task { await viewModel.load() }
        .accessibilityIdentifier("discover.queueBuilder")
    }

    private var header: some View {
        HStack(spacing: MinidiscSpacing.s) {
            NavigationLink {
                QueueBuilderView(viewModel: viewModel)
            } label: {
                MinidiscCarouselHeader("Queue Builder", showsChevron: true, horizontalPadding: 0)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full Queue Builder")
            Spacer(minLength: 0)
            if !viewModel.selection.isEmpty {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    HapticFeedback.light.trigger()
                    viewModel.reset()
                }
                .buttonStyle(.minidiscCircle(diameter: MinidiscControlSize.compact))
            }
            Button {
                HapticFeedback.medium.trigger()
                Task { await viewModel.build() }
            } label: {
                if viewModel.isBuilding {
                    ProgressView()
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .buttonStyle(.minidiscCircle(isProminent: true))
            .disabled(!viewModel.canBuild)
            .accessibilityLabel("Play queue")
        }
        .padding(.horizontal, MinidiscSpacing.l)
    }

    @ViewBuilder
    private var rows: some View {
        pillRow {
            ForEach(viewModel.index?.columns ?? []) { column in
                CardPill(
                    title: column.name,
                    isSelected: viewModel.isPicked(main: column.id),
                    isExpanded: viewModel.focusedMain == column.id,
                    tint: GenreTint.color(for: column.id)
                ) {
                    withAnimation(.snappy) { viewModel.tapMainInCard(column.id) }
                }
            }
        }
        if let column = viewModel.focusedColumn, !column.pills.isEmpty {
            pillRow {
                ForEach(column.pills) { pill in
                    CardPill(
                        title: pill.name,
                        isSelected: viewModel.isSelected(pill: pill.id, in: column.id),
                        tint: GenreTint.color(for: column.id)
                    ) {
                        viewModel.toggle(pill: pill.id, in: column.id)
                    }
                }
            }
            // A new identity per genre: each one's sub-genres start scrolled to the left instead of
            // inheriting the previous genre's scroll position.
            .id(column.id)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        pillRow {
            ForEach(viewModel.decades, id: \.self) { decade in
                CardPill(title: "\(String(decade))s", isSelected: viewModel.selection.decades.contains(decade)) {
                    viewModel.toggle(decade: decade)
                }
            }
        }
        if viewModel.isMoodAvailable {
            pillRow {
                ForEach(QueueBuilderMood.allCases) { mood in
                    CardPill(title: String(localized: mood.title), isSelected: viewModel.selection.moods.contains(mood)) {
                        viewModel.toggle(mood: mood)
                    }
                }
            }
        }
        summary
    }

    private var summary: some View {
        Text(verbatim: viewModel.summary)
        .font(.minidiscCaption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .padding(.horizontal, MinidiscSpacing.l)
    }

    private func pillRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: MinidiscSpacing.s) {
                content()
            }
            .padding(.horizontal, MinidiscSpacing.l)
        }
    }
}

/// A compact capsule pill for the Discover card. A picked main genre whose sub-genres are showing
/// gets a chevron, so the second row reads as belonging to it.
private struct CardPill: View {
    let title: String
    let isSelected: Bool
    var isExpanded = false
    /// The main genre's colour; nil for decades, moods and "Other".
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        let appearance = PillAppearance(tint: tint, isSelected: isSelected)
        Button {
            HapticFeedback.light.trigger()
            action()
        } label: {
            HStack(spacing: MinidiscSpacing.xs) {
                Text(verbatim: title)
                    .font(.minidiscCellSubtitle.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if isExpanded {
                    Image(systemName: "chevron.down")
                        .font(.minidiscCaption2.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, MinidiscSpacing.m)
            .padding(.vertical, MinidiscSpacing.s)
            .foregroundStyle(appearance.foreground)
            .background(appearance.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(appearance.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isExpanded ? Text("Showing its sub-genres below") : Text(""))
    }
}

#if DEBUG
private nonisolated struct PreviewQueueBuilderSource: QueueBuilderLibrarySource {
    func queueBuilderStamp() async throws -> String? { "preview" }
    func queueBuilderTracks() async throws -> [QueueBuilderTrack]? { Self.tracks }

    static let tracks: [QueueBuilderTrack] = {
        let shapes: [([String], Int, Int)] = [
            (["Modal"], 1959, 40), (["Fusion", "Contemporary Jazz"], 1976, 55), (["Contemporary Jazz"], 2004, 80),
            (["Hard Bop"], 1962, 35), (["Techno"], 1994, 120), (["House", "Deep House"], 2001, 70),
            (["IDM", "Ambient"], 1997, 45), (["Hip-Hop", "Conscious"], 1993, 60), (["Trip Hop"], 1995, 30),
            (["Alternative Rock"], 1991, 65), (["Punk Rock"], 1978, 25), (["Soul"], 1968, 40), (["Norway"], 2015, 5),
            (["Folk"], 1971, 20), (["Dub"], 1979, 15), (["Bossa Nova"], 1964, 12),
        ]
        var tracks: [QueueBuilderTrack] = []
        for (genres, year, count) in shapes {
            for index in 0..<count {
                let id = "\(genres[0])-\(index)"
                guard let song = try? JSONDecoder().decode(Song.self, from: Data("{\"id\":\"\(id)\",\"title\":\"\(id)\",\"isDir\":false}".utf8)) else { continue }
                tracks.append(QueueBuilderTrack(song: song, genres: genres, year: year + index % 8))
            }
        }
        return tracks
    }()
}

@MainActor
private func previewModel(_ container: AppContainer, picked: QueueBuilderSelection = QueueBuilderSelection()) -> QueueBuilderViewModel {
    let model = QueueBuilderViewModel(
        service: QueueBuilderService(source: PreviewQueueBuilderSource(), library: container.libraryService, moodScorer: PreviewMoodScorer()),
        playerService: container.playerService,
        toastService: container.toastService,
        defaults: UserDefaults(suiteName: "preview.queueBuilder.\(UUID().uuidString)") ?? .standard
    )
    model.loadForPreview(QueueBuilderIndex(tracks: PreviewQueueBuilderSource.tracks, taxonomy: .discogs), moodAvailable: true)
    model.selection = picked
    return model
}

private nonisolated struct PreviewMoodScorer: MoodScoring {
    func isAvailable() async -> Bool { true }
    func scores(for songIDs: [String]) async throws -> [String: AudioMuseMoodScores] { [:] }
}

#Preview("Queue Builder") {
    let container = AppContainer.preview()
    return MinidiscPreview(container: container) {
        NavigationStack { QueueBuilderView(viewModel: previewModel(container)) }
    }
}

#Preview("Queue Builder · picked") {
    let container = AppContainer.preview()
    let picked = QueueBuilderSelection(
        mains: ["Jazz"],
        tags: [GenreTaxonomy.discogs.resolve("Techno").key, GenreTaxonomy.discogs.resolve("IDM").key],
        decades: [1990, 2000],
        moods: [.relaxed]
    )
    return MinidiscPreview(container: container) {
        NavigationStack { QueueBuilderView(viewModel: previewModel(container, picked: picked)) }
    }
}

#Preview("Discover card") {
    let container = AppContainer.preview()
    let model = previewModel(container, picked: QueueBuilderSelection(
        mains: ["Hip Hop"], tags: [GenreTaxonomy.discogs.resolve("Modal").key], decades: [1990], moods: [.relaxed]
    ))
    model.tapMainInCard("Jazz")
    return MinidiscPreview(container: container) {
        NavigationStack {
            ScrollView { QueueBuilderCard(viewModel: model) }
        }
    }
}
#endif
