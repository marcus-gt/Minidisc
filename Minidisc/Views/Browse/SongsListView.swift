import SwiftUI
import SwiftSonic
import OSLog

struct SongsListView: View {
    @Environment(\.appContainer) private var container
    @State private var songSelection: SongSelectionRequest?
    @State private var viewModel: SongsListViewModel?
    @AppStorage("minidisc.songSort") private var songSort: SongSort = .title
    @State private var filterText = ""
    /// Songs matching `filterText`, or `nil` with no filter. Computed off the main actor: a library
    /// can hold hundreds of thousands of songs.
    @State private var filteredSongs: [DisplayableSong]?

    /// Everything the filter result depends on; a change re-runs it.
    private struct FilterKey: Equatable {
        let query: String
        let sort: SongSort
        let songCount: Int
        let isOnline: Bool
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .minidiscContentWidth()
        .navigationTitle("Songs")
        .toolbarTitleDisplayMode(.inline)
        .minidiscFilterable(text: $filterText, prompt: "Filter songs")
        .sheet(item: $songSelection) { SongSelectionSheet(request: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SongSortMenu(sort: $songSort)
                    .tint(.primary)
            }
            ToolbarItem(placement: .primaryAction) {
                MinidiscMoreMenu {
                    Button("Select Songs", systemImage: "checkmark.circle") {
                        songSelection = SongSelectionRequest(songs: filteredSongs ?? viewModel?.displaySongs ?? [])
                    }
                    .disabled(container?.serverState.isOnline != true
                              || (filteredSongs ?? viewModel?.displaySongs ?? []).isEmpty)
                }
                .tint(.primary)
            }
        }
        .task(id: loadID) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = SongsListViewModel(libraryService: svc) }
            if container?.serverState.isOnline == true { await viewModel?.load(sort: songSort) }
        }
        .onChange(of: songSort) { _, newSort in
            Task { await viewModel?.changeSort(newSort) }
        }
        .task(id: filterKey) { await applyFilter() }
    }

    private var filterKey: FilterKey? {
        guard let viewModel else { return nil }
        return FilterKey(query: filterText, sort: songSort, songCount: allSongs(viewModel).count,
                         isOnline: container?.serverState.isOnline == true)
    }

    private func applyFilter() async {
        guard let viewModel, let query = LibraryFilter.query(filterText) else {
            filteredSongs = nil
            return
        }
        // Debounce typing; a newer key cancels this task.
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        let matches = await Self.songs(allSongs(viewModel), matching: query)
        guard !Task.isCancelled else { return }
        filteredSongs = matches
    }

    @concurrent
    private static func songs(_ songs: [DisplayableSong], matching query: String) async -> [DisplayableSong] {
        LibraryFilter.filter(songs, by: query) { [$0.title, $0.artist, $0.albumName] }
    }

    private func displayedSongs(_ vm: SongsListViewModel) -> [DisplayableSong] {
        guard LibraryFilter.query(filterText) != nil, let filteredSongs else { return allSongs(vm) }
        return filteredSongs
    }

    private func allSongs(_ vm: SongsListViewModel) -> [DisplayableSong] {
        guard container?.serverState.isOnline == false else { return vm.displaySongs }
        let songs = container?.offlineLibrary.snapshot.songs ?? []
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return songSort.sorted(songs.map { $0.asSong() }).compactMap { byID[$0.id] }
    }

    @ViewBuilder
    private func content(_ vm: SongsListViewModel) -> some View {
        if container?.serverState.isOnline != false && vm.isLoading && allSongs(vm).isEmpty {
            loadingProgress(vm)
        } else if container?.serverState.isOnline == false && allSongs(vm).isEmpty {
            OfflineBrowsingEmptyView()
        } else if let error = vm.error, allSongs(vm).isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Songs",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load(sort: songSort) } }
            )
        } else if allSongs(vm).isEmpty {
            EmptyStateView(
                systemImage: "music.note",
                title: "No Songs",
                subtitle: "Your library appears to be empty."
            )
        } else if displayedSongs(vm).isEmpty {
            FilterNoResultsView(query: filterText)
        } else {
            songList(vm)
        }
    }

    private func loadingProgress(_ vm: SongsListViewModel) -> some View {
        VStack(spacing: MinidiscSpacing.m) {
            ProgressView()
            Text(vm.loadedCount == 0 ? "Loading songs…" : "\(vm.loadedCount.formatted()) songs loaded…")
                .font(.minidiscBody)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut, value: vm.loadedCount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func songList(_ vm: SongsListViewModel) -> some View {
        let songs = displayedSongs(vm)
        return ScrollViewReader { proxy in
            List {
                if container?.serverState.isOnline != false && vm.didTruncate {
                    Text("Showing the first \(allSongs(vm).count.formatted()) songs.")
                        .font(.minidiscCaption)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                playShuffleHeader(songs)
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 1, showCoverArt: true, isFavorite: isFavorite(song))
                        .contentShape(Rectangle())
                        .onTapGesture { play(songs, at: index) }
                        .id(song.id)
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh(vm) }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                // The A–Z jump bar only makes sense when sorted by title.
                if songSort == .title && songs.count >= 20 {
                    AlphabetJumpBar(
                        availableLetters: songs.availableAlphabetLetters(keyPath: \.title),
                        onLetterTap: { letter in
                            if let id = firstAlphabetItemID(forLetter: letter, in: songs, keyPath: \.title) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    )
                    .padding(.trailing, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func playShuffleHeader(_ songs: [DisplayableSong]) -> some View {
        HStack(spacing: MinidiscSpacing.m) {
            Button {
                HapticFeedback.medium.trigger()
                Task {
                    guard !songs.isEmpty else { return }
                    await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: 0, source: .songs) }
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MinidiscSpacing.s)
            }

            Button {
                HapticFeedback.medium.trigger()
                Task {
                    guard !songs.isEmpty else { return }
                    let idx = Int.random(in: 0..<songs.count)
                    await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: idx, source: .songs) }
                    if container?.playerState.isShuffled != true {
                        await container?.playerService.toggleShuffle()
                    }
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MinidiscSpacing.s)
            }
        }
        .buttonStyle(.bordered)
        .tint(.minidiscAccent)
        .disabled(songs.isEmpty)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.vertical, 4)
    }

    private func isFavorite(_ song: DisplayableSong) -> Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    private func play(_ songs: [DisplayableSong], at index: Int) {
        Task {
            do {
                try await container?.playerService.play(tracks: songs, startIndex: index, source: .songs)
            } catch {
                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                if !UserFacingError.isCancellation(error) {
                    container?.toastService.showError(UserFacingError.from(error).displayMessage)
                }
            }
        }
    }

    private var loadID: ServerAccessSnapshot? {
        container?.serverState.accessSnapshot
    }

    private func refresh(_ viewModel: SongsListViewModel) async {
        if container?.serverState.isOnline == true {
            try? await container?.libraryCatalog.refreshTracks()
        }
        if container?.serverState.isOnline == true { await viewModel.load(sort: songSort) }
        else { await container?.offlineLibrary.refresh() }
    }
}
