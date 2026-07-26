import Foundation
import SwiftUI

/// Owns catalogue state for the whole app: what is on screen, where it came
/// from, when it was last refreshed and what went wrong if anything did.
///
/// Update sequence, in order:
///  1. Publish the cached (or seeded) catalogue immediately so the app is
///     usable before any network work starts.
///  2. Fetch `version.json` and compare `catalogueVersion` with the cached one.
///  3. Download the content files only when the remote version is newer, or
///     when the caller forces a refresh.
///  4. Decode and validate every file before anything is written.
///  5. Swap the cache atomically. On any failure the previous working
///     catalogue is retained and the failure is surfaced in the status UI.
@MainActor
final class CatalogueService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case checking
        case downloading
        case ready
    }

    enum Outcome: Equatable {
        case upToDate
        case updated(from: Int, to: Int)
        case failed(CatalogueError)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    // MARK: - Published state

    @Published private(set) var snapshot: CatalogueSnapshot?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var source: CatalogueSource
    /// Timestamp of the last refresh that produced a usable catalogue.
    @Published private(set) var lastSuccessfulUpdate: Date?
    /// Timestamp of the last attempt, successful or not.
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastOutcome: Outcome?
    @Published private(set) var lastError: CatalogueError?
    /// Validation problems from the most recent rejected publish.
    @Published private(set) var lastValidationIssues: [CatalogueValidator.Issue] = []

    private let fetcher: CatalogueFetching
    private var cache: CatalogueCacheStore
    private let imageStore: ImageStore
    private var refreshTask: Task<Void, Never>?

    // MARK: - Derived state

    var isRefreshing: Bool { phase == .checking || phase == .downloading }

    /// True when what is on screen did not come from a successful network fetch.
    var isUsingOfflineData: Bool {
        guard let snapshot else { return true }
        return snapshot.isSeed || lastError != nil
    }

    var isOffline: Bool { lastError == .offline || lastError == .timedOut }

    var catalogueVersion: Int? { snapshot?.version.catalogueVersion }

    /// One-line summary for the status row on Settings and Home.
    var statusSummary: String {
        if isRefreshing { return phase == .checking ? "Checking for updates…" : "Downloading catalogue…" }
        if let error = lastError {
            return snapshot == nil ? "Catalogue unavailable" : "Using offline data — \(error.shortLabel.lowercased())"
        }
        if snapshot?.isSeed == true { return "Using bundled catalogue" }
        if snapshot == nil { return "Catalogue unavailable" }
        return "Catalogue up to date"
    }

    // MARK: - Init

    init(
        source: CatalogueSource,
        fetcher: CatalogueFetching = CatalogueRemoteClient(),
        imageStore: ImageStore
    ) {
        self.source = source
        self.fetcher = fetcher
        self.imageStore = imageStore
        self.cache = CatalogueCacheStore(source: source)
        loadFromDisk()
    }

    /// Load the cached catalogue, falling back to the bundled seed.
    private func loadFromDisk() {
        if let payload = cache.load(), let snapshot = decodeSnapshot(from: payload, source: source) {
            self.snapshot = snapshot
            lastSuccessfulUpdate = payload.retrievedAt
            phase = .ready
            return
        }
        if let seed = SeedCatalogue.load() {
            snapshot = seed
            lastSuccessfulUpdate = nil
            phase = .ready
        }
    }

    private func decodeSnapshot(
        from payload: CatalogueCacheStore.CachedPayload,
        source: CatalogueSource
    ) -> CatalogueSnapshot? {
        let decoder = JSONDecoder.catalogueDecoder
        guard
            let version = try? decoder.decode(CatalogueVersion.self, from: payload.version),
            let catalogue = try? decoder.decode(Catalogue.self, from: payload.catalogue),
            let bundles = try? decoder.decode(BundleCatalogue.self, from: payload.bundles),
            let announcements = try? decoder.decode(AnnouncementFeed.self, from: payload.announcements)
        else {
            return nil
        }
        return CatalogueSnapshot(
            version: version,
            catalogue: catalogue,
            bundleCatalogue: bundles,
            announcementFeed: announcements,
            retrievedAt: payload.retrievedAt,
            source: source
        )
    }

    // MARK: - Refresh

    /// Check for and apply a catalogue update.
    ///
    /// - Parameter force: download and re-validate even when the remote version
    ///   matches what is cached. Used by the manual Refresh Catalogue action.
    func refresh(force: Bool = false) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.performRefresh(force: force)
            self?.refreshTask = nil
        }
    }

    /// Async form used by pull-to-refresh, which needs to await completion.
    func refreshAndWait(force: Bool = false) async {
        refreshTask?.cancel()
        refreshTask = nil
        await performRefresh(force: force)
    }

    private func performRefresh(force: Bool) async {
        phase = .checking
        defer { phase = .ready }

        let activeSource = source
        let decoder = JSONDecoder.catalogueDecoder

        do {
            // 1. Version probe.
            let versionData = try await fetcher.fetch(activeSource.url(for: "version.json"))
            lastChecked = Date()

            let remoteVersion: CatalogueVersion
            do {
                remoteVersion = try decoder.decode(CatalogueVersion.self, from: versionData)
            } catch {
                throw CatalogueError.malformed("version.json")
            }

            // 2. Skip the download when nothing has changed.
            if !force,
               let current = snapshot,
               !current.isSeed,
               current.source == activeSource,
               current.version.catalogueVersion >= remoteVersion.catalogueVersion {
                lastError = nil
                lastValidationIssues = []
                lastOutcome = .upToDate
                return
            }

            phase = .downloading

            // 3. Content download.
            let names = remoteVersion.files
            async let catalogueBytes = fetcher.fetch(activeSource.url(for: names.catalogue))
            async let bundleBytes = fetcher.fetch(activeSource.url(for: names.bundles))
            async let announcementBytes = fetcher.fetch(activeSource.url(for: names.announcements))

            let catalogueData = try await catalogueBytes
            let bundlesData = try await bundleBytes
            let announcementsData = try await announcementBytes

            // 4. Decode, then validate. Either failing leaves the cache alone.
            let catalogue: Catalogue
            let bundles: BundleCatalogue
            let announcements: AnnouncementFeed
            do {
                catalogue = try decoder.decode(Catalogue.self, from: catalogueData)
            } catch {
                throw CatalogueError.malformed(names.catalogue)
            }
            do {
                bundles = try decoder.decode(BundleCatalogue.self, from: bundlesData)
            } catch {
                throw CatalogueError.malformed(names.bundles)
            }
            do {
                announcements = try decoder.decode(AnnouncementFeed.self, from: announcementsData)
            } catch {
                throw CatalogueError.malformed(names.announcements)
            }

            let validation = CatalogueValidator.validate(
                version: remoteVersion,
                catalogue: catalogue,
                bundles: bundles,
                announcements: announcements
            )
            guard validation.isAcceptable else {
                lastValidationIssues = validation.issues
                throw CatalogueError.rejected(validation.errors)
            }
            lastValidationIssues = validation.warnings

            // 5. Persist, then swap in memory.
            let retrievedAt = Date()
            var writeFailure: CatalogueError?
            do {
                try cache.store(
                    version: versionData,
                    catalogue: catalogueData,
                    bundles: bundlesData,
                    announcements: announcementsData,
                    catalogueVersion: remoteVersion.catalogueVersion,
                    sourceKey: activeSource.cacheKey,
                    retrievedAt: retrievedAt
                )
            } catch {
                // Content is good but this device could not store it. Use it for
                // this session and tell the user offline data will not persist.
                writeFailure = .cacheWriteFailed(error.localizedDescription)
            }

            let previousVersion = snapshot?.version.catalogueVersion ?? 0
            snapshot = CatalogueSnapshot(
                version: remoteVersion,
                catalogue: catalogue,
                bundleCatalogue: bundles,
                announcementFeed: announcements,
                retrievedAt: retrievedAt,
                source: activeSource
            )
            lastSuccessfulUpdate = retrievedAt
            lastError = writeFailure
            lastOutcome = writeFailure.map { Outcome.failed($0) }
                ?? .updated(from: previousVersion, to: remoteVersion.catalogueVersion)

            // 6. Warm the image cache so the catalogue works offline.
            if writeFailure == nil {
                let refs = catalogue.products.map(\.imageRef) + bundles.bundles.map(\.imageRef)
                await imageStore.prefetch(Array(Set(refs)))
            }
        } catch let error as CatalogueError {
            lastChecked = Date()
            lastError = error
            lastOutcome = .failed(error)
        } catch {
            lastChecked = Date()
            let wrapped = CatalogueError.offline
            lastError = wrapped
            lastOutcome = .failed(wrapped)
        }
    }

    // MARK: - Source switching

    /// Point the app at a different catalogue source. Each source keeps its own
    /// cache directory, so switching back and forth never mixes content.
    func switchSource(to newSource: CatalogueSource) {
        guard newSource != source else { return }
        refreshTask?.cancel()
        refreshTask = nil

        source = newSource
        cache = CatalogueCacheStore(source: newSource)
        imageStore.updateSource(newSource)
        lastError = nil
        lastOutcome = nil
        lastValidationIssues = []
        lastSuccessfulUpdate = nil
        snapshot = nil
        loadFromDisk()
        refresh(force: true)
    }

    // MARK: - Cache maintenance

    func cacheSizeDescription() -> String {
        // The cache store enumerates its whole directory tree, images included.
        ByteCountFormatter.string(fromByteCount: cache.cacheSizeInBytes(), countStyle: .file)
    }

    /// Drop everything cached for the current source and reload from the seed.
    func clearCache() {
        cache.clear()
        imageStore.clearCache()
        snapshot = nil
        lastSuccessfulUpdate = nil
        lastError = nil
        lastOutcome = nil
        lastValidationIssues = []
        loadFromDisk()
    }
}
