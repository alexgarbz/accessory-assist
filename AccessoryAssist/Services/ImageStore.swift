import SwiftUI
import UIKit

/// Loads product imagery with an offline-first strategy:
/// memory cache → device cache → image bundled with the app → network.
///
/// Anything fetched from the network is written to the device cache, so a store
/// that has loaded the catalogue once keeps working with no connection.
@MainActor
final class ImageStore: ObservableObject {

    private let fetcher: CatalogueFetching
    private var cache: CatalogueCacheStore
    private var source: CatalogueSource
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(source: CatalogueSource, fetcher: CatalogueFetching = CatalogueRemoteClient()) {
        self.source = source
        self.fetcher = fetcher
        self.cache = CatalogueCacheStore(source: source)
        memory.countLimit = 120
        memory.totalCostLimit = 48 * 1024 * 1024
    }

    func updateSource(_ newSource: CatalogueSource) {
        source = newSource
        cache = CatalogueCacheStore(source: newSource)
        memory.removeAllObjects()
        inFlight.removeAll()
    }

    /// Fetch an image, or `nil` when it cannot be resolved from any layer.
    ///
    /// Product photography hosted outside the catalogue is fetched from its own
    /// URL; imagery published with the catalogue is fetched relative to the
    /// current catalogue source. Either way the bytes land in the same device
    /// cache, so the catalogue keeps working with no connection.
    func image(for ref: CatalogueImageRef) async -> UIImage? {
        guard !ref.isEmpty, !ref.cacheKey.isEmpty else { return nil }
        let key = ref.cacheKey

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [source, cache, fetcher] in
            // Device cache.
            if let data = cache.cachedImageData(for: key), let image = UIImage(data: data) {
                return image
            }
            // Network, then persist for offline use.
            //
            // This is attempted before the copy bundled with the app, and the
            // order matters: replacing artwork at the same location is a
            // documented content operation, so a stale image shipped in the
            // binary must never win over the published one.
            let remoteURL = ref.absoluteURL ?? source.imageURL(for: key)
            if let data = try? await fetcher.fetch(remoteURL), let image = UIImage(data: data) {
                cache.storeImage(data, for: key)
                return image
            }
            // Fall back to an image shipped with the app, so a device that has
            // never had a connection still shows something.
            let stem = (key as NSString).deletingPathExtension
            return UIImage(named: stem)
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    /// Convenience for imagery published alongside the catalogue.
    func image(named imageName: String) async -> UIImage? {
        await image(for: CatalogueImageRef(cacheKey: imageName, absoluteURL: nil))
    }

    /// Warm the cache after a catalogue update so the app survives losing
    /// connectivity mid-shift. Bounded concurrency keeps it off the critical path.
    func prefetch(_ refs: [CatalogueImageRef]) async {
        let missing = refs.filter { ref in
            !ref.cacheKey.isEmpty
                && memory.object(forKey: ref.cacheKey as NSString) == nil
                && cache.cachedImageData(for: ref.cacheKey) == nil
        }
        guard !missing.isEmpty else { return }

        let batchSize = 4
        var index = 0
        while index < missing.count {
            let batch = Array(missing[index..<min(index + batchSize, missing.count)])
            await withTaskGroup(of: Void.self) { group in
                for ref in batch {
                    group.addTask { [weak self] in
                        _ = await self?.image(for: ref)
                    }
                }
            }
            index += batchSize
        }
    }

    /// Convenience for imagery published alongside the catalogue.
    func prefetch(_ imageNames: [String]) async {
        await prefetch(imageNames.map { CatalogueImageRef(cacheKey: $0, absoluteURL: nil) })
    }

    func cacheSizeInBytes() -> Int64 {
        var total: Int64 = 0
        let directory = cache.imageDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for url in contents {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    func clearCache() {
        memory.removeAllObjects()
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: cache.imageDirectory)
    }
}
