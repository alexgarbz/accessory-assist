import Foundation

/// On-disk cache of the last catalogue set that passed validation.
///
/// Raw response bytes are stored rather than re-encoded models, so what is
/// replayed on the next launch is byte-identical to what was validated. Writes
/// go to a staging directory and are swapped in atomically, so a crash or a
/// failed download can never leave a half-written catalogue behind.
struct CatalogueCacheStore {

    struct CachedPayload {
        let version: Data
        let catalogue: Data
        let bundles: Data
        let announcements: Data
        let retrievedAt: Date
    }

    private enum FileName {
        static let version = "version.json"
        static let catalogue = "catalogue.json"
        static let bundles = "bundles.json"
        static let announcements = "announcements.json"
        static let metadata = "cache-metadata.json"
    }

    private struct Metadata: Codable {
        let retrievedAt: Date
        let catalogueVersion: Int
        let sourceKey: String
    }

    private let fileManager: FileManager
    private let rootDirectory: URL

    init(source: CatalogueSource, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        rootDirectory = base
            .appendingPathComponent("Catalogue", isDirectory: true)
            .appendingPathComponent(source.cacheKey, isDirectory: true)
    }

    /// Directory holding cached images for this source.
    var imageDirectory: URL {
        rootDirectory.appendingPathComponent("images", isDirectory: true)
    }

    private var currentDirectory: URL {
        rootDirectory.appendingPathComponent("current", isDirectory: true)
    }

    private var stagingDirectory: URL {
        rootDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    // MARK: - Reading

    /// Load the cached payload, or `nil` when nothing valid is cached yet.
    func load() -> CachedPayload? {
        let directory = currentDirectory
        guard
            let versionData = try? Data(contentsOf: directory.appendingPathComponent(FileName.version)),
            let catalogueData = try? Data(contentsOf: directory.appendingPathComponent(FileName.catalogue)),
            let bundlesData = try? Data(contentsOf: directory.appendingPathComponent(FileName.bundles)),
            let announcementsData = try? Data(contentsOf: directory.appendingPathComponent(FileName.announcements))
        else {
            return nil
        }

        let metadataURL = directory.appendingPathComponent(FileName.metadata)
        let retrievedAt: Date
        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder.catalogueDecoder.decode(Metadata.self, from: metadataData) {
            retrievedAt = metadata.retrievedAt
        } else if let attributes = try? fileManager.attributesOfItem(atPath: metadataURL.path),
                  let modified = attributes[.modificationDate] as? Date {
            retrievedAt = modified
        } else {
            retrievedAt = Date()
        }

        return CachedPayload(
            version: versionData,
            catalogue: catalogueData,
            bundles: bundlesData,
            announcements: announcementsData,
            retrievedAt: retrievedAt
        )
    }

    // MARK: - Writing

    /// Atomically replace the cached catalogue.
    ///
    /// Everything is written to a staging directory first; only once all four
    /// files are on disk is the staging directory swapped for the live one.
    func store(
        version: Data,
        catalogue: Data,
        bundles: Data,
        announcements: Data,
        catalogueVersion: Int,
        sourceKey: String,
        retrievedAt: Date = Date()
    ) throws {
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        try version.write(to: stagingDirectory.appendingPathComponent(FileName.version), options: .atomic)
        try catalogue.write(to: stagingDirectory.appendingPathComponent(FileName.catalogue), options: .atomic)
        try bundles.write(to: stagingDirectory.appendingPathComponent(FileName.bundles), options: .atomic)
        try announcements.write(to: stagingDirectory.appendingPathComponent(FileName.announcements), options: .atomic)

        let metadata = Metadata(
            retrievedAt: retrievedAt,
            catalogueVersion: catalogueVersion,
            sourceKey: sourceKey
        )
        let metadataData = try JSONEncoder.catalogueEncoder.encode(metadata)
        try metadataData.write(to: stagingDirectory.appendingPathComponent(FileName.metadata), options: .atomic)

        // Swap: move the live directory aside, promote staging, then bin the old.
        let previousDirectory = rootDirectory.appendingPathComponent("previous", isDirectory: true)
        try? fileManager.removeItem(at: previousDirectory)
        if fileManager.fileExists(atPath: currentDirectory.path) {
            try fileManager.moveItem(at: currentDirectory, to: previousDirectory)
        }
        do {
            try fileManager.moveItem(at: stagingDirectory, to: currentDirectory)
        } catch {
            // Promotion failed — restore the previous copy so the app is never
            // left without a catalogue.
            if fileManager.fileExists(atPath: previousDirectory.path) {
                try? fileManager.moveItem(at: previousDirectory, to: currentDirectory)
            }
            throw error
        }
        try? fileManager.removeItem(at: previousDirectory)

        try? excludeFromBackup(rootDirectory)
    }

    // MARK: - Images

    func cachedImageURL(for imageName: String) -> URL {
        imageDirectory.appendingPathComponent(imageName)
    }

    func cachedImageData(for imageName: String) -> Data? {
        try? Data(contentsOf: cachedImageURL(for: imageName))
    }

    func storeImage(_ data: Data, for imageName: String) {
        guard !imageName.contains("/"), !imageName.contains("..") else { return }
        try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try? data.write(to: cachedImageURL(for: imageName), options: .atomic)
    }

    // MARK: - Maintenance

    /// Size on disk of everything cached for this source.
    func cacheSizeInBytes() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// Remove everything cached for this source. The app falls back to the
    /// bundled seed catalogue until the next successful refresh.
    func clear() {
        try? fileManager.removeItem(at: rootDirectory)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }
}

// MARK: - Shared coders

extension JSONDecoder {
    /// Decoder used for every catalogue file. ISO 8601 timestamps throughout.
    static var catalogueDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.catalogueFractional.date(from: raw) {
                return date
            }
            if let date = ISO8601DateFormatter.catalogueStandard.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp, found \"\(raw)\"."
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var catalogueEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension ISO8601DateFormatter {
    static let catalogueStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let catalogueFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
