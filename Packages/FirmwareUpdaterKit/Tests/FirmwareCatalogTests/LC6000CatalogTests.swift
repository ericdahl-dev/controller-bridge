import Foundation
import Testing
import FirmwareCatalog
import FirmwareModel

@Test func aUnitOnTheTestedVersionsGetsThePatchSetForBothChips() throws {
    let catalog = try Catalog(directory: fixture("lc6000"))
    let set = try #require(catalog.patchSet(for: LC6000Firmware(wd: "00.50", tp: "00.31")))
    #expect(set.entries.map(\.chip) == [.wd, .tp])
    #expect(set.entries.map(\.file.lastPathComponent) == ["wd-one.patch", "tp-one.patch"])
}

@Test func aUnitWithEitherChipOnAnotherVersionGetsNoPatchSet() throws {
    let catalog = try Catalog(directory: fixture("lc6000"))
    #expect(catalog.patchSet(for: LC6000Firmware(wd: "00.51", tp: "00.31")) == nil)
    #expect(catalog.patchSet(for: LC6000Firmware(wd: "00.50", tp: "00.30")) == nil)
    #expect(catalog.patchSet(for: LC6000Firmware(wd: "", tp: "")) == nil)
}
