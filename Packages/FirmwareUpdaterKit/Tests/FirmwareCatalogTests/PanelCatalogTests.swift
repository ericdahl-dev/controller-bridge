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
