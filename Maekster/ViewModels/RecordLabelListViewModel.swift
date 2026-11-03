import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class RecordLabelListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        /// Labels are read from indexed albums; the Subsonic API cannot list them.
        case waitingForIndex
        case failed(UserFacingError)
    }

    private(set) var labels: [RecordLabelSummary] = []
    private(set) var state: LoadState = .loading

    private let library: any RecordLabelBrowsing

    init(library: any RecordLabelBrowsing) {
        self.library = library
    }

    func load() async {
        if labels.isEmpty { state = .loading }
        do {
            let loaded = try await library.recordLabels()
            try Task.checkCancellation()
            guard let loaded else {
                state = .waitingForIndex
                return
            }
            labels = loaded
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            Logger.library.warning("Record label list failed: \(UserFacingError.from(error).id, privacy: .public)")
            state = .failed(UserFacingError.from(error))
        }
    }
}
