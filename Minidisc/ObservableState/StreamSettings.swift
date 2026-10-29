import Foundation
import Observation

/// Selects server transcoding quality separately for Wi-Fi and cellular connections, and for downloads.
@Observable
@MainActor
final class StreamSettings {
    @ObservationIgnored private var _wifiQuality: StreamQuality
    @ObservationIgnored private var _cellularQuality: StreamQuality
    @ObservationIgnored private var _downloadQuality: StreamQuality
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isCellular = false

    var wifiQuality: StreamQuality {
        get {
            access(keyPath: \.wifiQuality)
            return _wifiQuality
        }
        set {
            withMutation(keyPath: \.wifiQuality) { _wifiQuality = newValue }
            defaults.set(newValue.rawValue, forKey: Self.wifiKey)
        }
    }

    var cellularQuality: StreamQuality {
        get {
            access(keyPath: \.cellularQuality)
            return _cellularQuality
        }
        set {
            withMutation(keyPath: \.cellularQuality) { _cellularQuality = newValue }
            defaults.set(newValue.rawValue, forKey: Self.cellularKey)
        }
    }

    /// What new downloads ask the server for (#32). Downloads already on the device keep theirs.
    var downloadQuality: StreamQuality {
        get {
            access(keyPath: \.downloadQuality)
            return _downloadQuality
        }
        set {
            withMutation(keyPath: \.downloadQuality) { _downloadQuality = newValue }
            defaults.set(newValue.rawValue, forKey: Self.downloadKey)
        }
    }

    var currentQuality: StreamQuality { isCellular ? cellularQuality : wifiQuality }

    static let defaultWifiQuality: StreamQuality = .original
    static let defaultCellularQuality: StreamQuality = .mp3_192
    /// Downloads were always the original file before the setting existed.
    static let defaultDownloadQuality: StreamQuality = .original

    private static let wifiKey = "minidisc.stream.wifiQuality"
    private static let cellularKey = "minidisc.stream.cellularQuality"
    private static let downloadKey = "minidisc.download.quality"
    /// Pre-split single-quality key; used to seed both tiers on upgrade.
    private static let legacyKey = "minidisc.stream.quality"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let legacy = defaults.string(forKey: Self.legacyKey)
        let wifiRaw = defaults.string(forKey: Self.wifiKey) ?? legacy
        let cellularRaw = defaults.string(forKey: Self.cellularKey) ?? legacy
        _wifiQuality = StreamQuality(rawValue: wifiRaw ?? "") ?? Self.defaultWifiQuality
        _cellularQuality = StreamQuality(rawValue: cellularRaw ?? "") ?? Self.defaultCellularQuality
        _downloadQuality = StreamQuality(rawValue: defaults.string(forKey: Self.downloadKey) ?? "") ?? Self.defaultDownloadQuality
    }

    /// Fed by the app-wide NetworkMonitor so connectivity is observed by a single system monitor.
    func networkPathDidChange(isCellular: Bool) {
        self.isCellular = isCellular
    }
}
