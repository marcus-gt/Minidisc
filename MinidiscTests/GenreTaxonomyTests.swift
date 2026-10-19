import Testing
@testable import Minidisc

@Suite("GenreTaxonomy")
struct GenreTaxonomyTests {
    private let taxonomy = GenreTaxonomy.discogs

    @Test func bundledMap_hasTheFifteenDiscogsGenres() {
        #expect(taxonomy.mainGenres.count == 15)
        #expect(taxonomy.mainGenres.contains("Jazz"))
        #expect(taxonomy.mainGenres.contains("Folk, World, & Country"))
    }

    @Test func discogsStyle_landsUnderItsMainGenre() {
        let techno = taxonomy.resolve("Techno")
        #expect(techno.mains == ["Electronic"])
        #expect(techno.styleName == "Techno")
    }

    @Test func styleInTwoGenres_belongsToBoth() {
        #expect(Set(taxonomy.resolve("Experimental").mains) == ["Electronic", "Rock"])
        #expect(Set(taxonomy.resolve("Trip Hop").mains) == ["Electronic", "Hip Hop"])
    }

    @Test func spellingVariants_shareAKey() {
        #expect(taxonomy.resolve("Hip-Hop").key == taxonomy.resolve("hip hop").key)
        #expect(taxonomy.resolve("Post Bop").key == taxonomy.resolve("post-bop").key)
        #expect(taxonomy.resolve("Drum And Bass").key == taxonomy.resolve("Drum n Bass").key)
    }

    @Test func mainGenreName_beatsAStyleWithTheSameName() {
        // Discogs also lists "Hip Hop" as an Electronic style.
        let hipHop = taxonomy.resolve("Hip-Hop")
        #expect(hipHop.mains == ["Hip Hop"])
        #expect(hipHop.isMainTag)
    }

    @Test func styleWithMainWord_mergesIntoTheStyle() {
        #expect(taxonomy.resolve("Modal Jazz").key == taxonomy.resolve("Modal").key)
        #expect(taxonomy.resolve("Jazz Fusion").key == taxonomy.resolve("Fusion").key)
    }

    @Test func keywordAndKnownSubgenres_getTheirOwnPill() {
        let eastCoast = taxonomy.resolve("East Coast Hip Hop")
        #expect(eastCoast.mains == ["Hip Hop"])
        #expect(!eastCoast.isMainTag)
        let thirdStream = taxonomy.resolve("Third Stream")
        #expect(thirdStream.mains == ["Jazz"])
        #expect(!thirdStream.isMainTag)
    }

    @Test func synonymsAndAccents_resolveToTheMainGenre() {
        #expect(taxonomy.resolve("Rap").isMainTag)
        #expect(taxonomy.resolve("Rap").mains == ["Hip Hop"])
        #expect(taxonomy.resolve("Électronique").mains == ["Electronic"])
    }

    @Test func unknownTag_goesToOther() {
        #expect(taxonomy.resolve("Norway").mains == [GenreTaxonomy.otherGenre])
    }
}
