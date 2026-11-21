import Foundation
import Testing
import FirmwareCatalog
import FirmwareModel
import FirmwareRelease

@Test func aSignedReleaseNewerThanTheBuiltInIsOfferedFromTheFeed() async throws {
    let primary = TestKey(id: "primary")
    let feed = release(panelVersion: "1.1.0", sha: "ddddddd", signedBy: primary)
    let fetcher = ReleaseFetcher(feed: feed, trusting: [primary.trusted], cache: temporaryFolder())
    let outcome = await fetcher.fetch(over: try builtIn(panelVersion: "1.0.0", sha: "aaaaaaa"))
    let newest = try #require(outcome.catalog.newestPanel())
    #expect(newest.version == FirmwareVersion("1.1.0"))
    #expect(try Data(contentsOf: newest.image) == panelImage("1.1.0"))
}
