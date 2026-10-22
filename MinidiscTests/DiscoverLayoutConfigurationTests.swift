import Testing
@testable import Minidisc

@Suite("DiscoverLayoutConfiguration")
@MainActor
struct DiscoverLayoutConfigurationTests {
    @Test func default_keepsDiscoversOriginalOrder() {
        #expect(DiscoverLayoutConfiguration.default.visibleSections == [
            .freshReleases, .stations, .smartShuffle, .queueBuilder, .moods, .wrapped, .internetRadio,
        ])
    }

    @Test func rawValue_roundTrip_keepsOrderAndHidden() throws {
        var config = DiscoverLayoutConfiguration.default
        // Settings always hands over the full order after a drag.
        config.setOrder([.smartShuffle, .moods] + DiscoverSection.allCases.filter { $0 != .smartShuffle && $0 != .moods })
        config.setVisible(false, for: .freshReleases)

        let decoded = try #require(DiscoverLayoutConfiguration(rawValue: config.rawValue))

        #expect(decoded == config)
        #expect(decoded.visibleSections.prefix(2) == [.smartShuffle, .moods])
        #expect(!decoded.visibleSections.contains(.freshReleases))
    }

    @Test func decode_sectionsAddedLater_landInTheirDefaultPlaceVisible() throws {
        // A layout saved before two sections existed (queueBuilder and internetRadio), with Wrapped moved first.
        let raw = #"{"hidden":[],"order":["wrapped","freshReleases","stations","smartShuffle","moods"]}"#
        let decoded = try #require(DiscoverLayoutConfiguration(rawValue: raw))
        #expect(decoded.order == [.wrapped, .internetRadio, .freshReleases, .stations, .smartShuffle, .queueBuilder, .moods])
        #expect(decoded.isVisible(.queueBuilder))
        #expect(decoded.isVisible(.internetRadio))
    }

    @Test func storageKey_isSeparateFromHome() {
        #expect(DiscoverLayoutConfiguration.storageKey != HomeLayoutConfiguration.storageKey)
    }
}
