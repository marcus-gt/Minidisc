import Testing
@testable import Minidisc

@Suite("HomeLayoutConfiguration")
@MainActor
struct HomeLayoutConfigurationTests {
    @Test func default_showsEverySectionInDeclarationOrder() {
        #expect(HomeLayoutConfiguration.default.visibleSections == HomeSection.allCases)
    }

    @Test func queueBuilder_isShownByDefaultWithoutAStyleChoice() {
        #expect(HomeLayoutConfiguration.default.isVisible(.queueBuilder))
        #expect(HomeLayoutConfiguration.default.order.prefix(3) == [.pinned, .playlists, .queueBuilder])
        #expect(!HomeSection.queueBuilder.supportsLayoutChoice)
    }

    @Test func layoutSavedBeforeTheQueueBuilder_getsItAppendedVisible() throws {
        let saved = #"{"hidden":["rediscover"],"order":["playlists","favoriteSongs","favoriteAlbums","recentlyPlayed","heavyRotation","rediscover","relevantAdditions","recentlyAdded","genres"]}"#
        let decoded = try #require(HomeLayoutConfiguration(rawValue: saved))
        #expect(decoded.order.prefix(4) == [.pinned, .playlists, .queueBuilder, .favoriteSongs])
        #expect(decoded.isVisible(.queueBuilder))
        #expect(!decoded.isVisible(.rediscover))
    }

    @Test func newSection_followsPlaylistsWhereverTheUserMovedThem() throws {
        let saved = #"{"hidden":[],"order":["recentlyPlayed","genres","playlists","favoriteSongs","favoriteAlbums","heavyRotation","rediscover","relevantAdditions","recentlyAdded"]}"#
        let decoded = try #require(HomeLayoutConfiguration(rawValue: saved))
        #expect(decoded.order.prefix(5) == [.pinned, .recentlyPlayed, .genres, .playlists, .queueBuilder])
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
        // Pinned didn't exist when this was saved, so it lands first (#44).
        #expect(decoded.order.prefix(3) == [.pinned, .genres, .playlists])
        #expect(!decoded.isVisible(.rediscover))
    }

    @Test func rawValue_roundTrip_keepsOrderAndHidden() throws {
        var config = HomeLayoutConfiguration.default
        config.setOrder([.genres, .playlists])
        config.setVisible(false, for: .rediscover)

        let decoded = try #require(HomeLayoutConfiguration(rawValue: config.rawValue))

        #expect(decoded == config)
        #expect(decoded.order.prefix(3) == [.pinned, .genres, .playlists])
        #expect(!decoded.isVisible(.rediscover))
    }

    @Test func decode_unknownSections_areDropped() throws {
        // A full saved order with recentlyPlayed moved first, plus a section this version doesn't know.
        let others = HomeSection.allCases.filter { $0 != .recentlyPlayed }.map { "\"\($0.rawValue)\"" }
        let raw = #"{"order":["recentlyPlayed","removedInFuture","# + others.joined(separator: ",") + #"],"hidden":["alsoGone"]}"#

        let decoded = try #require(HomeLayoutConfiguration(rawValue: raw))

        #expect(decoded.order.first == .recentlyPlayed)
        #expect(decoded.order.count == HomeSection.allCases.count)
        #expect(decoded.hidden.isEmpty)
    }

    @Test func decode_missingSections_landInTheirDefaultPlaceVisible() throws {
        let raw = #"{"order":["genres"],"hidden":[]}"#

        let decoded = try #require(HomeLayoutConfiguration(rawValue: raw))

        // Every missing section goes after its default predecessor, which rebuilds the default order.
        #expect(decoded.order == HomeSection.allCases)
        #expect(decoded.visibleSections.count == HomeSection.allCases.count)
    }

    /// A layout saved before the Pinned shelf existed shows it, at the top (#44).
    @Test func pinnedShelf_appearsFirstInAnOlderLayout() throws {
        let saved = HomeSection.allCases.filter { $0 != .pinned }.map { "\"\($0.rawValue)\"" }
        let raw = #"{"order":["# + saved.joined(separator: ",") + #"],"hidden":["genres"]}"#
        let decoded = try #require(HomeLayoutConfiguration(rawValue: raw))
        #expect(decoded.order.first == .pinned)
        #expect(decoded.isVisible(.pinned))
        #expect(!decoded.isVisible(.genres))
        #expect(!HomeSection.pinned.supportsLayoutChoice)
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
