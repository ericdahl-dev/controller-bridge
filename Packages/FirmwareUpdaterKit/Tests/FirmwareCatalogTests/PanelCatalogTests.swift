import Foundation
import Testing
import FirmwareCatalog
import FirmwareModel

func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
}

@Test func theNewestPanelFirmwareIsTheHighestVersionNotTheLastListed() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    let newest = try #require(catalog.newestPanel())
    #expect(newest.version == FirmwareVersion("1.10.0"))
    #expect(newest.sha == "bbbbbbb")
}

@Test func aPanelOnAnOlderShippedBuildIsOfferedTheNewest() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    let newest = try #require(catalog.newestPanel())
    #expect(catalog.offer(for: PanelBuild(sha: "ccccccc")) == .update(newest))
}

@Test func aPanelOnTheNewestBuildIsUpToDate() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    #expect(catalog.offer(for: PanelBuild(sha: "bbbbbbb")) == .upToDate)
}

@Test func aPanelOnABuildTheCatalogNeverShippedIsUnknownAndStillOffered() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    let newest = try #require(catalog.newestPanel())
    #expect(catalog.offer(for: PanelBuild(sha: "1234567")) == .unknownBuild(newest))
}

@Test func theBootLineShaMayBeLongerThanTheCatalogs() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    #expect(catalog.offer(for: PanelBuild(sha: "bbbbbbb0123")) == .upToDate)
}

@Test func aPanelThatReportsAnOlderVersionIsOfferedAnUpdateWhateverItsSha() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    let newest = try #require(catalog.newestPanel())
    #expect(catalog.offer(for: PanelBuild(sha: "1234567", version: FirmwareVersion("1.9.9"))) == .update(newest))
}

@Test func aPanelThatReportsTheNewestVersionOrLaterIsUpToDate() throws {
    let catalog = try Catalog(directory: fixture("one-panel"))
    #expect(catalog.offer(for: PanelBuild(sha: "1234567", version: FirmwareVersion("1.10.0"))) == .upToDate)
    #expect(catalog.offer(for: PanelBuild(sha: "ccccccc", version: FirmwareVersion("2.0"))) == .upToDate)
}
