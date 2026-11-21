import Foundation
import Testing
@testable import FirmwareRelease

/// The maintainer's key on disk (ADR 0012, #701): sealed with a passphrase, opened only with it.
@Test func aSealedKeyOpensWithItsPassphraseAndSignsAsBefore() throws {
    let key = SigningKey.generate(id: "primary")
    let file = try KeyFile.seal(key, passphrase: "correct horse battery staple")
    let opened = try KeyFile.open(file, passphrase: "correct horse battery staple")
    #expect(opened.id == "primary")
    let manifest = Data("manifest".utf8)
    #expect(key.trusted.signed(manifest, try opened.sign(manifest)))
}

@Test func aSealedKeyDoesNotOpenWithAnotherPassphrase() throws {
    let file = try KeyFile.seal(SigningKey.generate(id: "primary"), passphrase: "correct horse battery staple")
    #expect(throws: KeyFileError.wrongPassphraseOrDamaged) { try KeyFile.open(file, passphrase: "correct horse battery stapler") }
}

/// The id and public key are bound to the sealed seed, so a file relabelled as the backup key doesn't open.
@Test func aKeyFileWhoseNameWasChangedDoesNotOpen() throws {
    let file = try KeyFile.seal(SigningKey.generate(id: "primary"), passphrase: "pass phrase")
    let relabelled = Data(String(decoding: file, as: UTF8.self).replacingOccurrences(of: #""primary""#, with: #""backup""#).utf8)
    #expect(throws: KeyFileError.wrongPassphraseOrDamaged) { try KeyFile.open(relabelled, passphrase: "pass phrase") }
}

@Test func theKeyFileNeverHoldsTheSeedInTheClear() throws {
    let key = SigningKey.generate(id: "primary")
    let file = try KeyFile.seal(key, passphrase: "pass phrase")
    #expect(file.range(of: key.secret.rawRepresentation) == nil)
    #expect(file.range(of: Data(key.secret.rawRepresentation.base64EncodedString().utf8)) == nil)
}
