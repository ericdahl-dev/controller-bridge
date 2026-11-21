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

@Test func aReleaseWhoseSignatureDoesNotMatchIsRefusedAndTheBuiltInStays() async throws {
    let primary = TestKey(id: "primary")
    let feed = release(panelVersion: "1.1.0", sha: "ddddddd", signedBy: primary)
    feed.signature = TestKey(id: "primary").sign(feed.manifest)  // a different key claiming to be the primary
    let builtIn = try builtIn(panelVersion: "1.0.0", sha: "aaaaaaa")
    let outcome = await ReleaseFetcher(feed: feed, trusting: [primary.trusted], cache: temporaryFolder()).fetch(over: builtIn)
    #expect(outcome.refusal == .badSignature)
    #expect(outcome.catalog.newestPanel()?.version == FirmwareVersion("1.0.0"))
}

@Test func aManifestChangedAfterSigningIsRefused() async throws {
    let primary = TestKey(id: "primary")
    let feed = release(panelVersion: "1.1.0", sha: "ddddddd", signedBy: primary)
    feed.manifest = Data(String(decoding: feed.manifest, as: UTF8.self).replacingOccurrences(of: "1.1.0", with: "9.9.9").utf8)
    let outcome = await ReleaseFetcher(feed: feed, trusting: [primary.trusted], cache: temporaryFolder())
        .fetch(over: try builtIn(panelVersion: "1.0.0", sha: "aaaaaaa"))
    #expect(outcome.refusal == .badSignature)
}
