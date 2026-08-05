import Testing
@testable import CmuxUpdater

@Suite struct UpdateFeedResolverTests {
    @Test func defaultFallbackUsesCanonicalRepository() {
        let resolution = UpdateFeedResolver().resolve(infoFeedURL: nil)

        #expect(
            resolution.url
                == "https://github.com/Enigma-Labs-Technology/zerocmux/releases/latest/download/appcast.xml"
        )
        #expect(resolution.usedFallback)
        #expect(!resolution.isNightly)
    }

    @Test func missingInfoFeedURLUsesFallback() {
        let resolver = UpdateFeedResolver(fallbackFeedURL: "https://example.com/appcast.xml")
        let resolution = resolver.resolve(infoFeedURL: nil)
        #expect(resolution.url == "https://example.com/appcast.xml")
        #expect(resolution.usedFallback)
        #expect(!resolution.isNightly)
    }

    @Test func emptyInfoFeedURLUsesFallback() {
        let resolver = UpdateFeedResolver(fallbackFeedURL: "https://example.com/appcast.xml")
        let resolution = resolver.resolve(infoFeedURL: "")
        #expect(resolution.url == "https://example.com/appcast.xml")
        #expect(resolution.usedFallback)
    }

    @Test func stableInfoFeedURLIsUsedVerbatim() {
        let resolver = UpdateFeedResolver()
        let resolution = resolver.resolve(infoFeedURL: "https://example.com/stable/appcast.xml")
        #expect(resolution.url == "https://example.com/stable/appcast.xml")
        #expect(!resolution.usedFallback)
        #expect(!resolution.isNightly)
    }

    @Test func nightlyInfoFeedURLIsClassifiedNightly() {
        let resolver = UpdateFeedResolver()
        let resolution = resolver.resolve(infoFeedURL: "https://example.com/nightly/appcast.xml")
        #expect(resolution.isNightly)
        #expect(!resolution.usedFallback)
    }

    @Test(
        arguments: [
            (
                "zerocmux 1.2.3",
                "https://github.com/Enigma-Labs-Technology/zerocmux/releases/tag/v1.2.3"
            ),
            (
                "zerocmux 9a66d2c12242d6cb5e63f298c9ad37e86f86413f",
                "https://github.com/Enigma-Labs-Technology/zerocmux/commit/9a66d2c12242d6cb5e63f298c9ad37e86f86413f"
            ),
        ]
    )
    func releaseNotesUseCanonicalRepository(displayVersion: String, expectedURL: String) throws {
        let releaseNotes = try #require(UpdateState.ReleaseNotes(displayVersionString: displayVersion))

        #expect(releaseNotes.url.absoluteString == expectedURL)
    }
}
