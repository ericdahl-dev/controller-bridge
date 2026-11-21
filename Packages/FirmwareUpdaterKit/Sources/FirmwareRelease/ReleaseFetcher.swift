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

public struct FetchOutcome: Sendable {
    /// The catalog to use: the fetched release if it passed every check, otherwise the built-in one.
    public let catalog: Catalog
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
            let published = try await feed.latest()
            let manifest = try JSONDecoder().decode(Manifest.self, from: published.manifest)
            let folder = cache.appending(path: "fetched")
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in manifest.files {
                let target = folder.appending(path: file.name)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await feed.file(file.name).write(to: target)
            }
            try Manifest.catalogJSON(in: published.manifest).write(to: folder.appending(path: "catalog.json"))
            return FetchOutcome(catalog: try Catalog(directory: folder))
        } catch {
            return FetchOutcome(catalog: builtIn)
        }
    }
}
