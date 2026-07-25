import Foundation

/// The catalogue compiled into the app.
///
/// Guarantees a first launch with no network still shows a usable catalogue,
/// and gives the update flow something to fall back to if the on-disk cache is
/// ever unreadable. It is a snapshot of `remote-data/` at build time and is
/// expected to be stale — the UI always labels it as such.
enum SeedCatalogue {

    static func load(bundle: Foundation.Bundle = .main) -> CatalogueSnapshot? {
        guard
            let versionData = data(named: "version", in: bundle),
            let catalogueData = data(named: "catalogue", in: bundle),
            let bundlesData = data(named: "bundles", in: bundle),
            let announcementsData = data(named: "announcements", in: bundle)
        else {
            return nil
        }

        let decoder = JSONDecoder.catalogueDecoder
        guard
            let version = try? decoder.decode(CatalogueVersion.self, from: versionData),
            let catalogue = try? decoder.decode(Catalogue.self, from: catalogueData),
            let bundleCatalogue = try? decoder.decode(BundleCatalogue.self, from: bundlesData),
            let announcements = try? decoder.decode(AnnouncementFeed.self, from: announcementsData)
        else {
            return nil
        }

        return CatalogueSnapshot(
            version: version,
            catalogue: catalogue,
            bundleCatalogue: bundleCatalogue,
            announcementFeed: announcements,
            retrievedAt: version.publishedAt ?? Date(timeIntervalSince1970: 0),
            source: .production,
            isSeed: true
        )
    }

    private static func data(named name: String, in bundle: Foundation.Bundle) -> Data? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}
