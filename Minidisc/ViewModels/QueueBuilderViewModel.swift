import Foundation
import Observation
import OSLog
import SwiftSonic

/// State for the Queue Builder (#17), shared by the Discover card and the full page: pick genres,
/// decades and moods, choose a length, build and play. Picks and length are remembered per server.
@Observable @MainActor
final class QueueBuilderViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let lengthRange: ClosedRange<Double> = 15...120
    static let lengthStep: Double = 5
    static let defaultLength: Double = 50

    private(set) var phase: Phase = .loading
    private(set) var index: QueueBuilderIndex?
    private(set) var isBuilding = false
    /// AudioMuse is set up for this server, so the mood section shows.
    private(set) var isMoodAvailable = false
    /// The main genre whose sub-genres the Discover card shows in its second row.
    private(set) var focusedMain: String?
    var selection = QueueBuilderSelection() {
        didSet { if selection != oldValue { savePicks() } }
    }
    var length: Double = QueueBuilderViewModel.defaultLength {
        didSet { if length != oldValue { defaults.set(length, forKey: lengthKey) } }
    }
    var searchText = ""

    private let service: QueueBuilderService
    private let playerService: any PlayerServiceProtocol
    private let toastService: ToastService
    private let defaults: UserDefaults
    private let selectionKey: String
    private let lengthKey: String
    private var genreFallbackTask: Task<Void, Never>?

    /// `storageScope` keeps picks apart per server: genre keys come from that server's library.
    init(
        service: QueueBuilderService,
        playerService: any PlayerServiceProtocol,
        toastService: ToastService,
        defaults: UserDefaults = .standard,
        storageScope: String = "default"
    ) {
        self.service = service
        self.playerService = playerService
        self.toastService = toastService
        self.defaults = defaults
        selectionKey = "minidisc.queueBuilder.selection.\(storageScope)"
        lengthKey = "minidisc.queueBuilder.length.\(storageScope)"
        if let data = defaults.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(QueueBuilderSelection.self, from: data) {
            selection = saved
        }
        if let saved = defaults.object(forKey: lengthKey) as? Double, Self.lengthRange.contains(saved) {
            length = saved
        }
    }

    // MARK: - Loading

    func load() async {
        if index == nil { phase = .loading }
        do {
            let loaded = try await service.index()
            index = loaded
            isMoodAvailable = await service.isMoodAvailable()
            dropUnavailablePicks()
            phase = .ready
            if isMoodAvailable { fillGenresFromAudioMuse() }
        } catch is CancellationError {
            return
        } catch {
            Logger.library.error("[QUEUE-BUILDER] loading genres failed: \(error, privacy: .public)")
            if index == nil { phase = .failed(UserFacingError.from(error).displayMessage) }
        }
    }

    /// Untagged tracks get a main genre from AudioMuse in the background; the card shows the tag-only
    /// index meanwhile and picks up the filled one when it is ready.
    private func fillGenresFromAudioMuse() {
        guard genreFallbackTask == nil else { return }
        let service = service
        genreFallbackTask = Task { [weak self] in
            let changed = await service.fillUntaggedGenres()
            if changed, let filled = try? await service.index() {
                self?.index = filled
            }
            self?.genreFallbackTask = nil
        }
    }

    /// Saved picks can outlive the library (a genre retagged away) or AudioMuse (disconnected).
    /// Picks that can no longer be shown are removed so they never silently narrow a build.
    private func dropUnavailablePicks() {
        guard let index else { return }
        var cleaned = selection
        let mains = Set(index.columns.map(\.id))
        let tags = Set(index.columns.flatMap { $0.pills.map(\.id) })
        cleaned.mains.formIntersection(mains)
        cleaned.tags.formIntersection(tags)
        if !index.decadeCounts.isEmpty { cleaned.decades.formIntersection(index.decadeCounts.keys) }
        if !isMoodAvailable { cleaned.moods = [] }
        if cleaned != selection { selection = cleaned }
        if let focusedMain, !mains.contains(focusedMain) { self.focusedMain = nil }
    }

    // MARK: - Genres

    /// Columns filtered by the search text: a column stays when its name or any of its pills match.
    var visibleColumns: [QueueBuilderIndex.Column] {
        guard let index else { return [] }
        let query = GenreTaxonomy.normalized(searchText)
        guard !query.isEmpty else { return index.columns }
        return index.columns.compactMap { column in
            if GenreTaxonomy.normalized(column.name).contains(query) { return column }
            let pills = column.pills.filter { GenreTaxonomy.normalized($0.name).contains(query) }
            return pills.isEmpty ? nil : QueueBuilderIndex.Column(id: column.id, songCount: column.songCount, pills: pills)
        }
    }

    var focusedColumn: QueueBuilderIndex.Column? {
        guard let focusedMain else { return nil }
        return index?.columns.first { $0.id == focusedMain }
    }

    /// The whole genre is picked (full page column title).
    func isSelected(main: String) -> Bool { selection.mains.contains(main) }

    /// The genre is picked in whole or through some of its sub-genres (Discover card).
    func isPicked(main: String) -> Bool {
        if selection.mains.contains(main) { return true }
        guard let column = index?.columns.first(where: { $0.id == main }) else { return false }
        return column.pills.contains { selection.tags.contains($0.id) }
    }

    /// A pill counts as picked when picked itself or when its whole column is.
    func isSelected(pill: String, in main: String) -> Bool {
        selection.tags.contains(pill) || selection.mains.contains(main)
    }

    /// Full page column title: picks the whole genre, or unpicks it when it already is.
    func toggle(main: String) {
        if selection.mains.contains(main) {
            selection.mains.remove(main)
        } else {
            removeTags(of: main)
            selection.mains.insert(main)
        }
    }

    /// Discover card main-genre pill. Unpicked: picks the whole genre and shows its sub-genres.
    /// Picked while another genre's sub-genres show: shows this one's. Picked and showing: unpicks it.
    func tapMainInCard(_ main: String) {
        if !isPicked(main: main) {
            selection.mains.insert(main)
            focusedMain = main
        } else if focusedMain != main {
            focusedMain = main
        } else {
            selection.mains.remove(main)
            removeTags(of: main)
            focusedMain = nil
        }
    }

    /// A sub-genre pill, in the card or the full page. On a fully picked genre it narrows the genre
    /// to just this sub-genre; otherwise it toggles the sub-genre.
    func toggle(pill: String, in main: String) {
        if selection.mains.contains(main) {
            selection.mains.remove(main)
            selection.tags.insert(pill)
            return
        }
        if selection.tags.remove(pill) == nil { selection.tags.insert(pill) }
    }

    func clearGenres() {
        selection.mains = []
        selection.tags = []
        focusedMain = nil
    }

    private func removeTags(of main: String) {
        guard let column = index?.columns.first(where: { $0.id == main }) else { return }
        selection.tags.subtract(column.pills.map(\.id))
    }

    // MARK: - Decades

    /// Decades present in the library, newest first; the standard 2020s–1920s while counts are unknown.
    var decades: [Int] {
        guard let index, !index.decadeCounts.isEmpty else { return Array(stride(from: 2020, through: 1920, by: -10)) }
        return index.decadeCounts.keys.sorted(by: >)
    }

    func decadeCount(_ decade: Int) -> Int? { index?.decadeCounts[decade] }

    func toggle(decade: Int) {
        if selection.decades.remove(decade) == nil { selection.decades.insert(decade) }
    }

    func clearDecades() { selection.decades = [] }

    // MARK: - Moods

    func toggle(mood: QueueBuilderMood) {
        if selection.moods.remove(mood) == nil { selection.moods.insert(mood) }
    }

    func clearMoods() { selection.moods = [] }

    /// Clears every pick (genres, decades, moods); the length stays.
    func reset() {
        selection = QueueBuilderSelection()
        focusedMain = nil
        searchText = ""
    }

    // MARK: - Summary

    /// One line for the Discover card, e.g. "Jazz, Techno · 1960s · Relaxed".
    var summary: String {
        var parts: [String] = []
        let genres = pickedGenreNames
        if !genres.isEmpty { parts.append(ListFormatter.localizedString(byJoining: genres)) }
        if !selection.decades.isEmpty {
            parts.append(ListFormatter.localizedString(byJoining: selection.decades.sorted(by: >).map { "\($0)s" }))
        }
        if !selection.moods.isEmpty {
            let moods = QueueBuilderMood.allCases.filter(selection.moods.contains).map { String(localized: $0.title) }
            parts.append(ListFormatter.localizedString(byJoining: moods))
        }
        return parts.isEmpty ? String(localized: "Anything in your library") : parts.joined(separator: " · ")
    }

    /// Picked genres in column order: whole genres by name, otherwise their picked sub-genres.
    private var pickedGenreNames: [String] {
        guard let index else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        for column in index.columns {
            if selection.mains.contains(column.id) {
                names.append(column.name)
                continue
            }
            for pill in column.pills where selection.tags.contains(pill.id) && seen.insert(pill.id).inserted {
                names.append(pill.name)
            }
        }
        return names
    }

    // MARK: - Building

    /// Exact number of matching songs, or `nil` while counts are approximate.
    var matchCount: Int? {
        guard let index, !index.isApproximate else { return nil }
        return index.matchCount(selection)
    }

    var canBuild: Bool { phase == .ready && !isBuilding && matchCount != 0 }

    func build() async {
        guard canBuild else { return }
        isBuilding = true
        defer { isBuilding = false }
        let selection = selection
        let service = service
        let count = Int(length)
        do {
            let result = try await service.buildQueue(selection, count: count)
            guard !result.songs.isEmpty else {
                toastService.show(String(localized: "No songs match these picks. Try a broader selection."), style: .info)
                return
            }
            try await playerService.playBuiltQueue(result.songs.map { DisplayableSong(from: $0) }) { excluded, refillCount in
                try await service.buildQueue(selection, count: refillCount, excluding: excluded)
                    .songs.map { DisplayableSong(from: $0) }
            }
            if result.ignoredMoods {
                toastService.show(String(localized: "AudioMuse could not be reached, so moods were left out."), style: .info)
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.library.error("[QUEUE-BUILDER] build failed: \(error, privacy: .public)")
            toastService.showError(UserFacingError.from(error).displayMessage)
        }
    }

    #if DEBUG
    /// Previews render loaded straight away instead of capturing the loading state.
    func loadForPreview(_ index: QueueBuilderIndex, moodAvailable: Bool) {
        self.index = index
        isMoodAvailable = moodAvailable
        phase = .ready
    }
    #endif

    // MARK: - Persistence

    private func savePicks() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionKey)
    }
}
