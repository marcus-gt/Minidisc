import OSLog
import SwiftSonic
import SwiftUI

/// The Discover section: the iPhone's Discover page with Mac shelves, in the order and with the
/// sections chosen under Discover › Discover Screen. The cards (Smart Shuffle, Queue Builder, Song
/// Path, moods, stations, fresh releases) are the iPhone's, from `SharedViews/Discover`.
struct MacDiscoverView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: DiscoverViewModel?
    @State private var loadedServerID: UUID?
    @State private var radioStations: [InternetRadioStation] = []
    @State private var isStartingShuffle = false
    @State private var startingStationID: String?
    /// The library feed's first result is still being prepared (#15): show the shelf as loading.
    @State private var isPreparingFreshReleases = false
    @State private var editsLayout = false
    @State private var pageWidth: CGFloat = 0
    @AppStorage(DiscoverLayoutConfiguration.storageKey) private var layout: DiscoverLayoutConfiguration = .default

    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MaeksterSpacing.section) {
                if let viewModel {
                    ForEach(blocks) { block in
                        switch block {
                        case .section(let section): discoverSection(section, vm: viewModel)
                        case .cards(let sections): cardRow(sections, vm: viewModel)
                        }
                    }
                }
            }
            .padding(.vertical, MaeksterSpacing.l)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .navigationTitle("Discover")
        .navigationDestination(for: AlbumRecommendation.self) { release in
            FreshReleaseDetailView(release: release, providers: container?.externalProvidersStore.load() ?? [])
        }
        .toolbar {
            Button {
                editsLayout = true
            } label: {
                Label("Discover Screen", systemImage: "slider.horizontal.3")
            }
            .help("Discover Screen")
            Button {
                Task { await refresh(forceRefresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh")
            .disabled(!isOnline)
        }
        .sheet(isPresented: $editsLayout) {
            MacDiscoverLayoutSheet()
        }
        .task(id: container?.serverState.accessSnapshot) {
            guard let container else { return }
            let serverID = container.serverState.activeServer?.id
            // A server switch builds a new model, so one server's picks never show for another.
            if viewModel == nil || loadedServerID != serverID {
                loadedServerID = serverID
                viewModel = DiscoverViewModel(libraryService: container.libraryService,
                                              recommendationService: container.recommendationService)
                radioStations = []
            }
            await refresh(forceRefresh: false)
        }
        .task {
            // The library feed refreshes in the background and says when it has something new (#15).
            for await _ in NotificationCenter.default.notifications(named: .maeksterFreshReleasesChanged) {
                await viewModel?.loadFreshReleases()
                isPreparingFreshReleases = await container?.newReleasesService.isPreparing() ?? false
            }
        }
    }

    // MARK: - Sections

    /// One section, with the iPhone's availability rules: most need the server.
    @ViewBuilder
    private func discoverSection(_ section: DiscoverSection, vm: DiscoverViewModel) -> some View {
        switch section {
        case .freshReleases:
            if isOnline { freshReleases(vm) }
        case .stations:
            if isOnline {
                MacShelf(title: Text(section.title), items: vm.stations, cellWidth: 160) { station in
                    ArtistStationCard(station: station, isStarting: startingStationID == station.id) {
                        Task { await play(station) }
                    }
                }
            }
        case .smartShuffle, .songPath:
            if isAvailable(section) { cardRow([section], vm: vm) }
        case .queueBuilder:
            if isOnline, let queueBuilder = container?.queueBuilderViewModel() {
                // The card pads itself by `l`; the page margin is `xl`.
                QueueBuilderCard(viewModel: queueBuilder, isPanel: true)
                    .padding(.horizontal, MaeksterSpacing.xl - MaeksterSpacing.l)
            }
        case .moods:
            if isOnline {
                MacShelf(title: Text(section.title), items: Mood.allCases, cellWidth: 140) { MoodCard(mood: $0) }
            }
        case .internetRadio:
            if isOnline {
                MacShelf(title: Text(section.title), items: radioStations.map(MacRadioStation.init),
                         seeAll: .internetRadio, cellWidth: 140) {
                    RadioCard(station: $0.station)
                }
            }
        case .wrapped:
            EmptyView()
        }
    }

    // MARK: - Cards

    /// A page block: a section on its own, or Smart Shuffle and Song Path side by side when they
    /// follow each other.
    private enum Block: Identifiable {
        case section(DiscoverSection)
        case cards([DiscoverSection])

        var id: String {
            switch self {
            case .section(let section): section.rawValue
            case .cards(let sections): sections.map(\.rawValue).joined(separator: "+")
            }
        }
    }

    private static let cardSections: Set<DiscoverSection> = [.smartShuffle, .songPath]

    private var blocks: [Block] {
        var blocks: [Block] = []
        let shown = layout.visibleSections.filter { MacDiscoverLayoutSheet.listed.contains($0) }
        for section in shown {
            if Self.cardSections.contains(section) {
                guard isAvailable(section) else { continue }
                if case .cards(let previous) = blocks.last {
                    blocks[blocks.count - 1] = .cards(previous + [section])
                } else {
                    blocks.append(.cards([section]))
                }
            } else {
                blocks.append(.section(section))
            }
        }
        return blocks
    }

    private func isAvailable(_ section: DiscoverSection) -> Bool {
        switch section {
        case .smartShuffle: isOnline || container?.offlineLibrary.snapshot.songs.isEmpty == false
        case .songPath: SongPathAvailability.isAvailable(container)
        default: true
        }
    }

    /// Cards share a row at equal height when the window is wide enough, and stack when it isn't.
    private func cardRow(_ sections: [DiscoverSection], vm: DiscoverViewModel) -> some View {
        let layout = pageWidth >= MacDiscoverMetrics.sideBySideWidth && sections.count > 1
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: MaeksterSpacing.section))
        return layout {
            ForEach(sections) { section in
                card(section, vm: vm)
                    .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Each card pads itself by `l`; the page margin is `xl`.
        .padding(.horizontal, MaeksterSpacing.xl - MaeksterSpacing.l)
    }

    @ViewBuilder
    private func card(_ section: DiscoverSection, vm: DiscoverViewModel) -> some View {
        switch section {
        case .smartShuffle:
            SmartShuffleCard(coverIDs: shuffleCoverIDs(vm), isStarting: isStartingShuffle, fillsHeight: true) {
                Task { await smartShuffle() }
            }
        case .songPath:
            SongPathCard(fillsHeight: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func freshReleases(_ vm: DiscoverViewModel) -> some View {
        if !vm.freshReleases.isEmpty {
            MacShelf(title: Text(DiscoverSection.freshReleases.title), items: vm.freshReleases.map(MacFreshRelease.init),
                     seeAll: .freshReleases) { item in
                FreshReleaseAlbumCell(release: item.release)
            }
        } else if isPreparingFreshReleases {
            VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                Text(DiscoverSection.freshReleases.title)
                    .font(.maeksterShelfTitle)
                ProgressView()
            }
            .padding(.horizontal, MaeksterSpacing.xl)
        }
    }

    // MARK: - Actions

    private func refresh(forceRefresh: Bool) async {
        guard let viewModel, isOnline else { return }
        async let personal: Void = viewModel.load(forceRefresh: forceRefresh)
        async let releases: Void = refreshFreshReleases(viewModel)
        async let radio: Void = loadRadioStations(forceRefresh: forceRefresh)
        _ = await (personal, releases, radio)
    }

    /// New releases by artists in the library, from MusicBrainz (#15).
    private func refreshFreshReleases(_ model: DiscoverViewModel) async {
        await model.loadFreshReleases()
        isPreparingFreshReleases = await container?.newReleasesService.isPreparing() ?? false
    }

    private func loadRadioStations(forceRefresh: Bool) async {
        guard let radioService = container?.radioService else { return }
        do {
            let stations = try await radioService.listStations(forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            radioStations = stations
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            Logger.radio.error("[DISCOVER] radio stations failed: \(error, privacy: .public)")
        }
    }

    private func shuffleCoverIDs(_ vm: DiscoverViewModel) -> [String] {
        var seen = Set<String>()
        let albums = isOnline ? vm.recentlyPlayed + vm.mostPlayed : container?.offlineLibrary.snapshot.albums ?? []
        return albums.map { $0.coverArt ?? $0.id }
            .filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    private func play(_ station: ArtistStation) async {
        guard let container else { return }
        startingStationID = station.id
        defer { if startingStationID == station.id { startingStationID = nil } }
        await container.toastService.perform {
            try await container.playerService.playInstantMix(from: .artist(id: station.id), startingWith: station.starter,
                                                            source: .artistRadio(id: station.id, name: station.artist.name))
        }
    }

    private func smartShuffle() async {
        guard let container, !isStartingShuffle else { return }
        isStartingShuffle = true
        defer { isStartingShuffle = false }
        do {
            try await container.playerService.playSmartShuffle()
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            if case MaeksterError.smartShuffleEmpty = error {
                container.toastService.showError(String(localized: "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."))
            } else {
                container.toastService.showError(String(localized: "Smart Shuffle failed. Please try again."))
            }
        }
    }
}

private enum MacDiscoverMetrics {
    /// Below this, Smart Shuffle and Song Path stack instead of sharing a row.
    static let sideBySideWidth: CGFloat = 900
}

/// A fresh release as a shelf item (releases have no stable ID of their own).
private struct MacFreshRelease: Identifiable {
    let release: AlbumRecommendation
    var id: AlbumRecommendation { release }
}

/// An internet radio station as a shelf item.
private struct MacRadioStation: Identifiable {
    let station: InternetRadioStation
    var id: String { station.id }
}

/// Every fresh release from the past three months, grouped by month (Discover's See All).
struct MacAllFreshReleases: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: AllFreshReleasesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                AllFreshReleasesView(vm: viewModel)
            } else {
                LoadingStateView()
            }
        }
        .navigationDestination(for: AlbumRecommendation.self) { release in
            FreshReleaseDetailView(release: release, providers: container?.externalProvidersStore.load() ?? [])
        }
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = AllFreshReleasesViewModel(recommendationService: container.recommendationService)
        }
    }
}

/// Discover › Discover Screen: which sections show and in what order (the iPhone's Settings ›
/// Discover Screen). Wrapped isn't listed until the Mac has it.
private struct MacDiscoverLayoutSheet: View {
    @AppStorage(DiscoverLayoutConfiguration.storageKey) private var configuration: DiscoverLayoutConfiguration = .default
    @Environment(\.dismiss) private var dismiss

    static let listed = DiscoverSection.allCases.filter { $0 != .wrapped }

    var body: some View {
        MacSectionLayoutSheet(
            title: "Discover Screen",
            sections: configuration.order.filter(Self.listed.contains),
            label: \.title,
            isVisible: { configuration.isVisible($0) },
            setVisible: { configuration.setVisible($0, for: $1) },
            setListedOrder: { listed in
                var remaining = listed.makeIterator()
                configuration.setOrder(configuration.order.map { Self.listed.contains($0) ? (remaining.next() ?? $0) : $0 })
            },
            reset: { configuration = .default }
        )
    }
}
