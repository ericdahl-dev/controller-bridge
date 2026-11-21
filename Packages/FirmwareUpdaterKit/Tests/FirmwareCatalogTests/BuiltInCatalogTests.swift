import Foundation
import Testing
import FirmwareCatalog
import FirmwareModel

/// The flash kit's patch descriptions, the reference the app's copies must match byte for byte.
let kitPatches = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../../../../tools/lc6000-firmware/patches").standardized

@Test func theBuiltInCatalogFitsTheOwnersUnitWithSlot16AndNoDeckSelect() throws {
    let set = try #require(try Catalog.builtIn().patchSet(for: LC6000Firmware(wd: "00.50", tp: "00.31")))
    #expect(set.entries.map(\.file.lastPathComponent)
        == ["wd-00.50-show-slot-16.patch", "tp-00.31-no-deck-select-on-hello.patch"])
    #expect(set.entries.map(\.chip) == [.wd, .tp])
}

@Test func everyBuiltInPatchIsTheKitsFileByteForByte() throws {
    let sets = [try #require(try Catalog.builtIn().patchSet(for: LC6000Firmware(wd: "00.50", tp: "00.31")))]
    for entry in sets.flatMap(\.entries) {
        let kit = try Data(contentsOf: kitPatches.appending(path: entry.file.lastPathComponent))
        #expect(try Data(contentsOf: entry.file) == kit, "\(entry.file.lastPathComponent) differs from the kit's")
    }
}

/// Works offline (#684, story 21): everything the built-in catalog hands out is a file already on this Mac.
@Test func everythingTheBuiltInCatalogHandsOutIsALocalFile() throws {
    let set = try #require(try Catalog.builtIn().patchSet(for: LC6000Firmware(wd: "00.50", tp: "00.31")))
    for url in set.entries.map(\.file) {
        #expect(url.isFileURL)
        #expect(FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)), "\(url) is not on disk")
    }
}
