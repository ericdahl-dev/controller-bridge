import CryptoKit
import Foundation
import FirmwareCatalog

/// Where releases are published: this project's GitHub releases, or a fake in tests.
public protocol ReleaseFeed: Sendable {
    /// The newest release's manifest and its signature, as published.
    func latest() async throws -> PublishedRelease
    /// One file of that release, by the name the manifest gives it.
    func file(_ name: String) async throws -> Data
}

public struct PublishedRelease: Sendable {
    public let manifest: Data
    public let signature: Data

    public init(manifest: Data, signature: Data) {
        self.manifest = manifest
        self.signature = signature
    }
}

/// Why a fetched release wasn't used. The built-in catalog stays in use whatever the reason.
public enum Refusal: Error, Sendable, Equatable {
    case badSignature
    /// The manifest isn't one: cut short, empty, or not JSON.
    case unreadableManifest
    /// Signed, by its own account, with a key the app doesn't trust.
    case unknownKey(String)
    /// A file whose size or SHA-256 differs from the manifest: altered, or cut short.
    case fileMismatch(String)
}

public struct FetchOutcome: Sendable {
    /// The catalog to use: the fetched release if it passed every check, otherwise the built-in one.
    public let catalog: Catalog
    /// Why the fetched release wasn't used, or nil if it was.
    public var refusal: Refusal? = nil
}

public struct ReleaseFetcher: Sendable {
    let feed: any ReleaseFeed
    let keys: [TrustedKey]
    let cache: URL

    public init(feed: any ReleaseFeed, trusting keys: [TrustedKey], cache: URL) {
        self.feed = feed
        self.keys = keys
        self.cache = cache
    }

    public func fetch(over builtIn: Catalog) async -> FetchOutcome {
        do {
            return FetchOutcome(catalog: try await fetched())
        } catch let refusal as Refusal {
            return FetchOutcome(catalog: builtIn, refusal: refusal)
        } catch {
            return FetchOutcome(catalog: builtIn)
        }
    }

    private func fetched() async throws -> Catalog {
        let published = try await feed.latest()
        // Nothing in the manifest is used before its signature checks out, except the name of the key to check it with.
        guard let claimed = try? JSONDecoder().decode(KeyName.self, from: published.manifest).key else {
            throw Refusal.unreadableManifest
        }
        guard let key = keys.first(where: { $0.id == claimed }) else { throw Refusal.unknownKey(claimed) }
        guard key.signed(published.manifest, published.signature) else { throw Refusal.badSignature }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: published.manifest) else {
            throw Refusal.unreadableManifest
        }
        let folder = cache.appending(path: "fetched")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in manifest.files {
            let target = folder.appending(path: file.name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try await feed.file(file.name)
            guard data.count == file.size, sha256Hex(data) == file.sha256.lowercased() else {
                throw Refusal.fileMismatch(file.name)
            }
            try data.write(to: target)
        }
        try Manifest.catalogJSON(in: published.manifest).write(to: folder.appending(path: "catalog.json"))
        return try Catalog(directory: folder)
    }

    private struct KeyName: Decodable { let key: String }
}

func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
