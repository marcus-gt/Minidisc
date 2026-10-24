import Testing
@testable import Minidisc

@Suite("maekster brand identifiers")
struct MaeksterBrandTests {

    @Test func userAgent_hasNameVersionAndRepository() {
        #expect(MaeksterBrand.userAgent(version: "26.9.5") == "maekster/26.9.5 (https://github.com/marcus-gt/Minidisc)")
    }

    @Test func userAgent_default_usesTheLowercaseName() {
        #expect(MaeksterBrand.userAgent.hasPrefix("maekster/"))
        #expect(MaeksterBrand.userAgent.hasSuffix("(https://github.com/marcus-gt/Minidisc)"))
    }
}
