import Foundation
import Observation

@Observable
@MainActor
final class LyricsSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var _source: LyricsSource
    @ObservationIgnored private var _showsCurrentLineInPlayer: Bool
    @ObservationIgnored private var _timingOffsetMs: Int

    var source: LyricsSource {
        get {
            access(keyPath: \.source)
            return _source
        }
        set {
            withMutation(keyPath: \.source) {
                _source = newValue
            }
            defaults.set(newValue.rawValue, forKey: Self.sourceKey)
        }
    }

    /// The current lyric line under the title on the player screen (#36).
    var showsCurrentLineInPlayer: Bool {
        get {
            access(keyPath: \.showsCurrentLineInPlayer)
            return _showsCurrentLineInPlayer
        }
        set {
            withMutation(keyPath: \.showsCurrentLineInPlayer) {
                _showsCurrentLineInPlayer = newValue
            }
            defaults.set(newValue, forKey: Self.showsCurrentLineKey)
        }
    }

    /// Correction for lyrics that run early or late, in milliseconds. Positive shows each line later.
    var timingOffsetMs: Int {
        get {
            access(keyPath: \.timingOffsetMs)
            return _timingOffsetMs
        }
        set {
            let clamped = min(max(newValue, -Self.timingOffsetLimitMs), Self.timingOffsetLimitMs)
            withMutation(keyPath: \.timingOffsetMs) {
                _timingOffsetMs = clamped
            }
            defaults.set(clamped, forKey: Self.timingOffsetKey)
        }
    }

    static let defaultSource: LyricsSource = .automatic
    static let timingOffsetLimitMs = 3_000
    private static let sourceKey = "minidisc.lyrics.source"
    private static let showsCurrentLineKey = "minidisc.lyrics.showCurrentLineInPlayer"
    private static let timingOffsetKey = "minidisc.lyrics.timingOffsetMs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.sourceKey)
        _source = LyricsSource(rawValue: stored ?? "") ?? Self.defaultSource
        _showsCurrentLineInPlayer = defaults.object(forKey: Self.showsCurrentLineKey) as? Bool ?? true
        let offset = defaults.integer(forKey: Self.timingOffsetKey)
        _timingOffsetMs = min(max(offset, -Self.timingOffsetLimitMs), Self.timingOffsetLimitMs)
    }
}
