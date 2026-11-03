import Foundation
import Observation
import OSLog

/// Library → Genres (#49): main genres and their styles, from the indexed albums.
@Observable
@MainActor
final class GenreListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        /// Genres are grouped from indexed albums, like Labels.
        case waitingForIndex
        case failed(UserFacingError)
    }

    private(set) var genres: [MainGenreSummary] = []
    private(set) var state: LoadState = .loading

    private let library: any GenreBrowsing

    init(library: any GenreBrowsing) {
        self.library = library
    }

    func load() async {
        if genres.isEmpty { state = .loading }
        do {
            let loaded = try await library.genreLibrary()
            try Task.checkCancellation()
            guard let loaded else {
                state = .waitingForIndex
                return
            }
            genres = loaded
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            Logger.library.warning("Genre list failed: \(UserFacingError.from(error).id, privacy: .public)")
            state = .failed(UserFacingError.from(error))
        }
    }
}
