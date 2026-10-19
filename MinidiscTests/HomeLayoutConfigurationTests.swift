import Testing
@testable import Minidisc

@Suite("HomeLayoutConfiguration")
@MainActor
struct HomeLayoutConfigurationTests {
    @Test func default_showsEverySectionInDeclarationOrder() {
        #expect(HomeLayoutConfiguration.default.visibleSections == HomeSection.allCases)
    }

    @Test func equality_comparesFieldsNotEncodedStrings() {
        var config = HomeLayoutConfiguration.default
        config.setVisible(false, for: .rediscover)
        #expect(HomeLayoutConfiguration.default == HomeLayoutConfiguration.default)
        #expect(config == config)
        #expect(config != HomeLayoutConfiguration.default)
    }

    @Test func rawValue_isStableAcrossEncodes() {
        var config = HomeLayoutConfiguration.default
        config.setVisible(false, for: .rediscover)
        let encodings = Set((0..<50).map { _ in config.rawValue })
        #expect(encodings.count == 1)
    }

    @Test func rawValue_decodesValuesStoredWithEitherKeyOrder() throws {
        // Layouts saved before keys were sorted may have `order` first.
        let legacy = #"{"order":["genres","playlists"],"hidden":["rediscover"]}"#
        let decoded = try #require(HomeLayoutConfiguration(rawValue: legacy))
        #expect(decoded.order.prefix(2) == [.genres, .playlists])
        #expect(!decoded.isVisible(.rediscover))
    }

    @Test func rawValue_roundTrip_keepsOrderAndHidden() throws {
        var config = HomeLayoutConfiguration.default
        config.setOrder([.genres, .playlists])
        config.setVisible(false, for: .rediscover)

        let decoded = try #require(HomeLayoutConfiguration(rawValue: config.rawValue))

        #expect(decoded == config)
        #expect(decoded.order.prefix(2) == [.genres, .playlists])
        #expect(!decoded.isVisible(.rediscover))
    }

    @Test func decode_unknownSections_areDropped() throws {
        let raw = #"{"order":["recentlyPlayed","removedInFuture"],"hidden":["alsoGone"]}"#

        let decoded = try #require(HomeLayoutConfiguration(rawValue: raw))

        #expect(decoded.order.first == .recentlyPlayed)
        #expect(decoded.order.count == HomeSection.allCases.count)
        #expect(decoded.hidden.isEmpty)
    }

    @Test func decode_missingSections_areAppendedVisible() throws {
        let raw = #"{"order":["genres"],"hidden":[]}"#

        let decoded = try #require(HomeLayoutConfiguration(rawValue: raw))

        #expect(decoded.order == [.genres] + HomeSection.allCases.filter { $0 != .genres })
        #expect(decoded.visibleSections.count == HomeSection.allCases.count)
    }

    @Test func decode_garbage_returnsNil() {
        #expect(HomeLayoutConfiguration(rawValue: "not json") == nil)
    }

    @Test func setOrder_duplicates_areRemoved() {
        var config = HomeLayoutConfiguration.default
        config.setOrder([.playlists, .playlists, .genres])

        #expect(config.order.filter { $0 == .playlists }.count == 1)
        #expect(config.order.count == HomeSection.allCases.count)
    }

    @Test func hiddenSection_isExcludedFromVisibleSections() {
        var config = HomeLayoutConfiguration.default
        config.setVisible(false, for: .favoriteSongs)

        #expect(!config.visibleSections.contains(.favoriteSongs))
        config.setVisible(true, for: .favoriteSongs)
        #expect(config.visibleSections.contains(.favoriteSongs))
    }
}
