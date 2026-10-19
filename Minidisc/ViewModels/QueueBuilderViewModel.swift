import Foundation
import Observation
import OSLog
import SwiftSonic

/// State for the Queue Builder screen (#17): pick genres and decades, choose a length, build and play.
@Observable @MainActor
final class QueueBuilderViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let lengthRange: ClosedRange<Double> = 15...120
    static let lengthStep: Double = 5

    private(set) var phase: Phase = .loading
    private(set) var index: QueueBuilderIndex?
    private(set) var isBuilding = false
    /// AudioMuse is set up for this server, so the mood section shows.
    private(set) var isMoodAvailable = false
    var selection = QueueBuilderSelection()
    var length: Double = 50
    var searchText = ""

    private let service: QueueBuilderService
    private let playerService: any PlayerServiceProtocol
    private let toastService: ToastService

    init(service: QueueBuilderService, playerService: any PlayerServiceProtocol, toastService: ToastService) {
        self.service = service
        self.playerService = playerService
        self.toastService = toastService
    }

    // MARK: - Loading

    func load() async {
        if index == nil { phase = .loading }
        do {
            let loaded = try await service.index()
            index = loaded
            isMoodAvailable = await service.isMoodAvailable()
            if !isMoodAvailable { selection.moods = [] }
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            Logger.library.error("[QUEUE-BUILDER] loading genres failed: \(error, privacy: .public)")
            if index == nil { phase = .failed(UserFacingError.from(error).displayMessage) }
        }
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

    func isSelected(main: String) -> Bool { selection.mains.contains(main) }

    /// A pill counts as picked when picked itself or when its whole column is.
    func isSelected(pill: String, in main: String) -> Bool {
        selection.tags.contains(pill) || selection.mains.contains(main)
    }

    func toggle(main: String) {
        if selection.mains.remove(main) == nil { selection.mains.insert(main) }
    }

    func toggle(pill: String, in main: String) {
        if selection.mains.contains(main) {
            // Unpicking one pill of a picked column keeps the column's other pills picked.
            selection.mains.remove(main)
            let siblings = index?.columns.first { $0.id == main }?.pills.map(\.id) ?? []
            selection.tags.formUnion(siblings.filter { $0 != pill })
            return
        }
        if selection.tags.remove(pill) == nil { selection.tags.insert(pill) }
    }

    func clearGenres() {
        selection.mains = []
        selection.tags = []
    }

    // MARK: - Decades

    /// Decades present in the library, oldest first; the standard 1920s–2020s while counts are unknown.
    var decades: [Int] {
        guard let index, !index.decadeCounts.isEmpty else { return Array(stride(from: 1920, through: 2020, by: 10)) }
        return index.decadeCounts.keys.sorted()
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
}
