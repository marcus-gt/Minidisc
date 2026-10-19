import Testing
@testable import Minidisc

@Suite("DiscoverLayoutConfiguration")
@MainActor
struct DiscoverLayoutConfigurationTests {
    @Test func default_keepsDiscoversOriginalOrder() {
        #expect(DiscoverLayoutConfiguration.default.visibleSections == [
            .freshReleases, .stations, .smartShuffle, .moods, .wrapped, .internetRadio,
        ])
    }

    @Test func rawValue_roundTrip_keepsOrderAndHidden() throws {
        var config = DiscoverLayoutConfiguration.default
        config.setOrder([.smartShuffle, .moods])
        config.setVisible(false, for: .freshReleases)

        let decoded = try #require(DiscoverLayoutConfiguration(rawValue: config.rawValue))

        #expect(decoded == config)
        #expect(decoded.visibleSections.prefix(2) == [.smartShuffle, .moods])
        #expect(!decoded.visibleSections.contains(.freshReleases))
    }

    @Test func decode_sectionAddedLater_isAppendedVisible() throws {
        // A layout saved before a section existed (here: without internetRadio).
        let raw = #"{"hidden":[],"order":["wrapped","freshReleases","stations","smartShuffle","moods"]}"#
        let decoded = try #require(DiscoverLayoutConfiguration(rawValue: raw))
        #expect(decoded.order.first == .wrapped)
        #expect(decoded.order.last == .internetRadio)
        #expect(decoded.isVisible(.internetRadio))
    }

    @Test func storageKey_isSeparateFromHome() {
        #expect(DiscoverLayoutConfiguration.storageKey != HomeLayoutConfiguration.storageKey)
    }
}
