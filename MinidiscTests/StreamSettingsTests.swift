import Foundation
import Testing
@testable import Minidisc

@Suite("Stream settings")
@MainActor
struct StreamSettingsTests {
    @Test("The active quality follows the app-wide network path")
    func currentQualityFollowsNetworkPath() {
        let suiteName = "test.stream-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StreamSettings(defaults: defaults)
        settings.wifiQuality = .original
        settings.cellularQuality = .mp3_192

        settings.networkPathDidChange(isCellular: false)
        #expect(settings.currentQuality == .original)

        settings.networkPathDidChange(isCellular: true)
        #expect(settings.currentQuality == .mp3_192)
    }

    @Test("Quality choices persist independently")
    func qualityChoicesPersist() {
        let suiteName = "test.stream-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StreamSettings(defaults: defaults)
        settings.wifiQuality = .mp3_320
        settings.cellularQuality = .mp3_192

        let restored = StreamSettings(defaults: defaults)
        #expect(restored.wifiQuality == .mp3_320)
        #expect(restored.cellularQuality == .mp3_192)
    }

    /// Downloads have their own quality, untouched by the streaming tiers (#32).
    @Test("Download quality defaults to the original file and persists on its own")
    func downloadQualityIsSeparate() {
        let suiteName = "test.stream-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StreamSettings(defaults: defaults)
        #expect(settings.downloadQuality == .original)
        settings.wifiQuality = .mp3_192
        settings.downloadQuality = .mp3_320
        settings.networkPathDidChange(isCellular: true)

        let restored = StreamSettings(defaults: defaults)
        #expect(restored.downloadQuality == .mp3_320)
        #expect(restored.wifiQuality == .mp3_192)
    }
}
