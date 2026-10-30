import SwiftUI
import SwiftData
import OSLog

struct WrappedView: View {
    @Environment(\.appContainer) private var container
    @State private var selectedPeriod: WrappedPeriod = .currentMonth()
    @State private var data: WrappedData?
    @State private var isLoading = true
    @State private var wrappedPlaylistId: String?
    @State private var appeared = false
    @State private var loadFailed = false
    /// Where the shown recap came from, and how far back the history goes (#16).
    @State private var source: WrappedSourceKind?
    @State private var fellBack = false
    @State private var firstYear: Int?
    #if DEBUG
    @AppStorage("debug.wrappedFakeDataActive") private var overrideWithFakeData = false
    @AppStorage("debug.wrappedFakeDataJSON") private var persistedFakeDataJSON = ""
    #endif

    init(initialPeriod: WrappedPeriod = .currentMonth()) {
        _selectedPeriod = State(initialValue: initialPeriod)
    }

    /// The selected year's months (up to this month for the current year), then the year itself.
    private var availablePeriods: [WrappedPeriod] {
        let calendar = Calendar.current
        let now = Date()
        let thisYear = calendar.component(.year, from: now)
        let lastMonth = currentYear == thisYear ? calendar.component(.month, from: now) : 12
        var periods: [WrappedPeriod] = (1...lastMonth).map { .month(year: currentYear, month: $0) }
        periods.append(.year(currentYear))
        return periods
    }

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    /// Every year with listens, newest first. Only the current one without a ListenBrainz history.
    private var selectableYears: [Int] {
        Array((min(firstYear ?? thisYear, thisYear)...thisYear).reversed())
    }

    private var currentYear: Int {
        switch selectedPeriod {
        case .month(let year, _): return year
        case .year(let year): return year
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MinidiscSpacing.xl) {
                if selectableYears.count > 1 {
                    yearMenu
                }
                WrappedPeriodPicker(selectedPeriod: $selectedPeriod, availablePeriods: availablePeriods)
                sourceCaption

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, MinidiscSpacing.xxxxl)
                } else if loadFailed {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Recap",
                        subtitle: "Something went wrong. Pull to refresh.",
                        action: .init(label: "Retry") { Task { await loadData() } }
                    )
                } else if let d = data, d.totalTracksPlayed > 0 {
                    WrappedStatHero(data: d)
                        .cascadeAppear(order: 0, trigger: appeared)
                    WrappedTopArtistsSection(artists: d.topArtists)
                        .cascadeAppear(order: 1, trigger: appeared)
                    WrappedTopTracksSection(tracks: d.topTracks)
                        .cascadeAppear(order: 2, trigger: appeared)
                    WrappedTopAlbumsSection(albums: d.topAlbums)
                        .cascadeAppear(order: 3, trigger: appeared)
                    if case .year = selectedPeriod {
                        WrappedYearCard(
                            year: currentYear,
                            firstTrack: d.firstTrackOfPeriod,
                            lastTrack: d.lastTrackOfPeriod,
                            playlistId: wrappedPlaylistId
                        )
                        .cascadeAppear(order: 4, trigger: appeared)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.l)
            .padding(.bottom, MinidiscSpacing.xl)
        }
        .refreshable { await loadData(refresh: true) }
        .navigationTitle("")
        .task(id: selectedPeriod) {
            await loadData()
        }
        .task {
            guard let container, firstYear == nil else { return }
            firstYear = await container.wrappedDataSource.firstYear(calendar: .current)
        }
        .background {
            if let serverId = container?.serverState.activeServer?.id.uuidString {
                PlaybackEventWatcher(serverId: serverId) {
                    Task { await refreshData() }
                }
            }
        }
    }

    // MARK: - Year and source

    /// Picking a year shows that year's recap; its months are then in the picker below.
    private var yearMenu: some View {
        Menu {
            Picker("Year", selection: Binding(
                get: { currentYear },
                set: { year in selectedPeriod = year == thisYear ? .currentMonth() : .year(year) }
            )) {
                ForEach(selectableYears, id: \.self) { year in
                    Text(verbatim: String(year)).tag(year)
                }
            }
        } label: {
            HStack(spacing: MinidiscSpacing.xs) {
                Text(verbatim: String(currentYear))
                    .font(.minidiscDetailTitle)
                Image(systemName: "chevron.down")
                    .font(.minidiscCaption.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(Text("Year"))
        .accessibilityValue(Text(verbatim: String(currentYear)))
    }

    @ViewBuilder
    private var sourceCaption: some View {
        if fellBack {
            Label("ListenBrainz is unavailable, so this shows the plays recorded on this iPhone.", systemImage: "exclamationmark.triangle")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
        } else if source == .listenBrainz {
            Label("From your ListenBrainz history, across every player.", systemImage: "waveform")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
        } else if source == .device {
            Label("From the plays recorded on this iPhone. Connect ListenBrainz to include every player.", systemImage: "iphone")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MinidiscSpacing.s) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(Color.minidiscAccent.opacity(0.5))
            Text("No listens for this period.")
                .font(.minidiscCellTitle)
            Text("Listen up — we'll keep track of your activity.")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MinidiscSpacing.xxxxl)
    }

    // MARK: - Data loading

    private func refreshData() async {
        #if DEBUG
        guard !overrideWithFakeData else { return }
        #endif
        guard let container, let serverId = container.serverState.activeServer?.id.uuidString else { return }
        let result = await container.wrappedDataSource.wrappedData(for: selectedPeriod, serverId: serverId, calendar: .current)
        guard !Task.isCancelled else { return }
        data = result.data
        source = result.source
        fellBack = result.fellBack
    }

    private func loadData(refresh: Bool = false) async {
        #if DEBUG
        if overrideWithFakeData {
            guard isLoading,
                  !persistedFakeDataJSON.isEmpty,
                  let jsonData = persistedFakeDataJSON.data(using: .utf8),
                  let restored = try? JSONDecoder().decode(WrappedData.self, from: jsonData) else { return }
            selectedPeriod = restored.period
            data = restored
            isLoading = false
            loadFailed = false
            if case .year = restored.period { wrappedPlaylistId = "debug-playlist" }
            appeared = true
            return
        }
        #endif
        loadFailed = false
        guard let container, let serverId = container.serverState.activeServer?.id.uuidString else {
            isLoading = false
            loadFailed = true
            return
        }
        Logger.wrapped.debug("[WRAPPED-VIEW] fetch start period=\(selectedPeriod.displayName, privacy: .public)")
        appeared = false
        isLoading = true
        data = nil
        wrappedPlaylistId = nil
        let result = await container.wrappedDataSource.wrappedData(
            for: selectedPeriod, serverId: serverId, calendar: .current, refresh: refresh
        )
        guard !Task.isCancelled else { return }
        source = result.source
        fellBack = result.fellBack
        if case .year(let y) = selectedPeriod {
            wrappedPlaylistId = await container.wrappedPlaylistService.playlistId(year: y, serverId: serverId)
        }
        data = result.data
        isLoading = false
        appeared = true
        Logger.wrapped.debug("[WRAPPED-VIEW] fetch done totalPlays=\(result.data.totalTracksPlayed, privacy: .public)")
    }
}

// MARK: - Cascade appear modifier

private extension View {
    func cascadeAppear(order: Int, trigger: Bool) -> some View {
        self
            .opacity(trigger ? 1 : 0)
            .offset(y: trigger ? 0 : 16)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82).delay(Double(order) * 0.07),
                value: trigger
            )
    }
}

// MARK: - Server-scoped playback event watcher

private struct PlaybackEventWatcher: View {
    let onCountChange: () -> Void
    @Query private var events: [PlaybackEvent]

    init(serverId: String, onCountChange: @escaping () -> Void) {
        self.onCountChange = onCountChange
        let sid = serverId
        _events = Query(filter: #Predicate<PlaybackEvent> { $0.serverId == sid })
    }

    var body: some View {
        Color.clear
            .onChange(of: events.count) { _, _ in onCountChange() }
    }
}
