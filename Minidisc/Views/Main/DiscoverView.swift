import SwiftUI
import SwiftSonic

struct DiscoverView: View {
    @Environment(\.appContainer) private var container
    @State private var vm: DiscoverViewModel?
    @State private var loadedServerID: UUID?
    @State private var isStartingShuffle = false
    @State private var startingStationID: String?
    /// The first year with listens, for the Wrapped carousel (#69).
    @State private var wrappedFirstYear: Int?
    @State private var radioStations: [InternetRadioStation] = []
    @Namespace private var freshReleaseZoomNamespace
    @State private var showAllFreshReleases = false
    @State private var allReleasesVM: AllFreshReleasesViewModel?
    /// The library feed's first result is still being prepared (#15): show the card as loading.
    @State private var isPreparingFreshReleases = false
    @AppStorage(DiscoverLayoutConfiguration.storageKey) private var discoverLayout: DiscoverLayoutConfiguration = .default

    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MinidiscSpacing.section) {
                if let vm {
                    ForEach(discoverLayout.visibleSections) { section in
                        discoverSection(section, vm: vm)
                    }
                }
            }
            .padding(.top, MinidiscSpacing.m)
            .padding(.bottom, MinidiscSpacing.miniPlayerBottomMargin)
        }
        .navigationTitle("Discover")
        .toolbarTitleDisplayMode(.inlineLarge)
        .minidiscSettingsToolbar()
        .minidiscContentWidth()
        .task(id: container?.serverState.accessSnapshot) {
            guard let container else { return }
            let serverID = container.serverState.activeServer?.id
            if vm == nil || loadedServerID != serverID {
                loadedServerID = serverID
                vm = DiscoverViewModel(libraryService: container.libraryService,
                                       recommendationService: container.recommendationService)
                allReleasesVM = AllFreshReleasesViewModel(recommendationService: container.recommendationService)
                radioStations = []
            }
            if isOnline { await refreshDiscover(forceRefresh: false) }
        }
        .refreshable { await refreshDiscover(forceRefresh: true) }
        // The library feed refreshes in the background and says when it has something new (#15).
        .onReceive(NotificationCenter.default.publisher(for: .minidiscFreshReleasesChanged)) { _ in
            Task {
                await vm?.loadFreshReleases()
                await allReleasesVM?.loadReleases()
                isPreparingFreshReleases = await container?.newReleasesService.isPreparing() ?? false
            }
        }
        .navigationDestination(for: AlbumRecommendation.self) { release in
            FreshReleaseDetailView(
                release: release,
                providers: container?.externalProvidersStore.load() ?? []
            )
            .minidiscZoomTransition(
                sourceID: release.id ?? "\(release.artistName)-\(release.title)",
                in: freshReleaseZoomNamespace
            )
        }
        .navigationDestination(isPresented: $showAllFreshReleases) {
            if let allReleasesVM {
                AllFreshReleasesView(vm: allReleasesVM)
            }
        }
    }

    // MARK: - Sections

    /// One Discover section, shown in the order chosen in Settings. Each keeps its own availability
    /// rules: hiding a section in Settings never forces one that is unavailable offline to appear.
    @ViewBuilder
    private func discoverSection(_ section: DiscoverSection, vm: DiscoverViewModel) -> some View {
        switch section {
        case .freshReleases:
            if isOnline { freshReleasesSection(vm: vm) }
        case .stations:
            if isOnline { stationsSection(vm) }
        case .smartShuffle:
            if isOnline || container?.offlineLibrary.snapshot.songs.isEmpty == false {
                SmartShuffleCard(coverIDs: shuffleCoverIDs(vm), isStarting: isStartingShuffle) {
                    Task { await triggerSmartShuffle() }
                }
            }
        case .queueBuilder:
            if isOnline, let queueBuilder = container?.queueBuilderViewModel() {
                QueueBuilderCard(viewModel: queueBuilder)
            }
        case .moods:
            moodsSection
        case .wrapped:
            wrappedSection
        case .internetRadio:
            if isOnline { internetRadioSection }
        }
    }

    // MARK: - Moods

    /// A radio per mood (#60). It needs the server, so the shelf is hidden offline.
    @ViewBuilder
    private var moodsSection: some View {
        if isOnline {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                Text("Moods")
                    .font(.minidiscShelfTitle)
                    .padding(.horizontal, MinidiscSpacing.l)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: MinidiscSpacing.s) {
                        ForEach(Mood.allCases) { mood in
                            MoodCard(mood: mood)
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.l)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func freshReleasesSection(vm: DiscoverViewModel) -> some View {
        if !vm.freshReleases.isEmpty || isPreparingFreshReleases {
            FreshReleasesCard(
                releases: vm.freshReleases,
                isLoading: vm.freshReleases.isEmpty,
                onSeeAll: { showAllFreshReleases = true },
                zoomNamespace: freshReleaseZoomNamespace
            )
            .accessibilityIdentifier("discover.freshReleases")
        }
    }

    @ViewBuilder
    private func stationsSection(_ vm: DiscoverViewModel) -> some View {
        if !vm.stations.isEmpty {
            MinidiscShelf {
                MinidiscCarouselHeader("Stations for You", showsChevron: false)
                    .accessibilityIdentifier("discover.stations")
            } content: {
                ForEach(vm.stations) { station in
                    ArtistStationCard(station: station, isStarting: startingStationID == station.id) {
                        Task { await playStation(station) }
                    }
                }
            }
        }
    }

    private func shuffleCoverIDs(_ vm: DiscoverViewModel) -> [String] {
        var seen = Set<String>()
        let albums = isOnline ? vm.recentlyPlayed + vm.mostPlayed : container?.offlineLibrary.snapshot.albums ?? []
        return albums.map { $0.coverArt ?? $0.id }
            .filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    private func playStation(_ station: ArtistStation) async {
        guard let container else { return }
        startingStationID = station.id
        HapticFeedback.medium.trigger()
        defer { if startingStationID == station.id { startingStationID = nil } }
        await container.toastService.perform {
            try await container.playerService.playInstantMix(from: .artist(id: station.id), startingWith: station.starter)
        }
    }

    private func refreshDiscover(forceRefresh: Bool) async {
        guard let vm, isOnline else { return }
        async let personal: Void = vm.load(forceRefresh: forceRefresh)
        async let releases: Void = refreshFreshReleases(vm)
        async let radio: Void = loadRadioStations(forceRefresh: forceRefresh)
        async let mixes: Void = refreshServerMixes()
        _ = await (personal, releases, radio, mixes)
    }

    /// New releases by artists in the library, from MusicBrainz (#15); no ListenBrainz account needed.
    private func refreshFreshReleases(_ model: DiscoverViewModel) async {
        await model.loadFreshReleases()
        isPreparingFreshReleases = await container?.newReleasesService.isPreparing() ?? false
    }

    private func refreshServerMixes() async {
        guard let container, container.serverState.activeServer != nil else { return }
        let firstYear = await container.wrappedDataSource.firstYear(calendar: .current)
        guard !Task.isCancelled else { return }
        wrappedFirstYear = firstYear
    }

    private func triggerSmartShuffle() async {
        guard let container, !isStartingShuffle else { return }
        isStartingShuffle = true
        HapticFeedback.medium.trigger()
        defer { isStartingShuffle = false }
        do {
            try await container.playerService.playSmartShuffle()
        } catch {
            if !UserFacingError.isCancellation(error) {
                container.toastService.showError(smartShuffleErrorMessage(from: error))
            }
        }
    }

    private func smartShuffleErrorMessage(from error: Error) -> String {
        if case MinidiscError.smartShuffleEmpty = error {
            return String(localized: "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use.")
        }
        return String(localized: "Smart Shuffle failed. Please try again.")
    }

    private var wrappedSection: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            MinidiscCarouselHeaderLink(
                "Wrapped",
                itemCount: wrappedYears.count + 1,
                hasMore: true
            ) {
                WrappedYearlyListView()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: MinidiscSpacing.s) {
                    WrappedYearTile(period: .allTime)
                    ForEach(wrappedYears.prefix(MinidiscCarouselMetrics.previewLimit - 1), id: \.self) { year in
                        WrappedYearTile(year: year)
                    }
                }
                .padding(.horizontal, MinidiscSpacing.l)
            }
        }
    }

    /// One tile per year, newest first (#69).
    private var wrappedYears: [Int] {
        WrappedYears.years(firstYear: wrappedFirstYear)
    }

    private var internetRadioSection: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            MinidiscCarouselHeaderLink(
                "Internet Radio",
                itemCount: radioStations.count,
                hasMore: true
            ) {
                RadioListView()
            }

            if radioStations.isEmpty {
                NavigationLink {
                    RadioListView()
                } label: {
                    HStack(spacing: MinidiscSpacing.s) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(Color.minidiscAccent)
                        Text("Browse Stations")
                            .font(.minidiscCellTitle)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(MinidiscSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.minidiscAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MinidiscSpacing.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: MinidiscSpacing.s) {
                        ForEach(
                            Array(radioStations.prefix(MinidiscCarouselMetrics.previewLimit)),
                            id: \.id
                        ) { station in
                            RadioCard(station: station)
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.l)
                }
            }
        }
    }

    private func loadRadioStations(forceRefresh: Bool) async {
        guard let radioService = container?.radioService else { return }
        if let stations = try? await radioService.listStations(forceRefresh: forceRefresh) {
            guard !Task.isCancelled else { return }
            radioStations = stations
        }
    }

}
