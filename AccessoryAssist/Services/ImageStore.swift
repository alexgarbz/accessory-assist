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
    func image(named imageName: String) async -> UIImage? {
        guard !imageName.isEmpty else { return nil }

        if let cached = memory.object(forKey: imageName as NSString) {
            return cached
        }
        if let existing = inFlight[imageName] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [source, cache, fetcher] in
            // Device cache.
            if let data = cache.cachedImageData(for: imageName), let image = UIImage(data: data) {
                return image
            }
            // Network, then persist for offline use.
            //
            // This is attempted before the copy bundled with the app, and the
            // order matters: replacing artwork by overwriting the file in
            // images/ is a documented content operation, so a stale image
            // shipped in the binary must never win over the published one.
            if let data = try? await fetcher.fetch(source.imageURL(for: imageName)),
               let image = UIImage(data: data) {
                cache.storeImage(data, for: imageName)
                return image
            }
            // Fall back to the image shipped with the app (seed catalogue), so
            // a device that has never had a connection still shows something.
            let stem = (imageName as NSString).deletingPathExtension
            return UIImage(named: stem)
        }

        inFlight[imageName] = task
        let image = await task.value
        inFlight[imageName] = nil
        if let image {
            memory.setObject(image, forKey: imageName as NSString, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    /// Warm the cache after a catalogue update so the app survives losing
    /// connectivity mid-shift. Bounded concurrency keeps it off the critical path.
    func prefetch(_ imageNames: [String]) async {
        let missing = imageNames.filter { name in
            !name.isEmpty
                && memory.object(forKey: name as NSString) == nil
                && cache.cachedImageData(for: name) == nil
        }
        guard !missing.isEmpty else { return }

        let batchSize = 4
        var index = 0
        while index < missing.count {
            let batch = Array(missing[index..<min(index + batchSize, missing.count)])
            await withTaskGroup(of: Void.self) { group in
                for name in batch {
                    group.addTask { [weak self] in
                        _ = await self?.image(named: name)
                    }
                }
            }
            index += batchSize
        }
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
