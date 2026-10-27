import Foundation

nonisolated enum LyricsError: Error, Equatable, Sendable {
    case notSupportedByServer
    case notFound
    /// The provider is overloaded (HTTP 5xx) and the request is worth repeating.
    case serverBusy
    case networkError(underlying: String)
    case cacheCorrupted
}
