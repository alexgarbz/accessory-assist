import Foundation

/// Decoded contents of `version.json` — the small file the app polls on launch
/// to decide whether the larger content files need downloading at all.
struct CatalogueVersion: Decodable, Hashable {
    struct FileNames: Decodable, Hashable {
        let catalogue: String
        let bundles: String
        let announcements: String

        static let `default` = FileNames(
            catalogue: "catalogue.json",
            bundles: "bundles.json",
            announcements: "announcements.json"
        )

        init(catalogue: String, bundles: String, announcements: String) {
            self.catalogue = catalogue
            self.bundles = bundles
            self.announcements = announcements
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            catalogue = try container.decodeIfPresent(String.self, forKey: .catalogue) ?? FileNames.default.catalogue
            bundles = try container.decodeIfPresent(String.self, forKey: .bundles) ?? FileNames.default.bundles
            announcements = try container.decodeIfPresent(String.self, forKey: .announcements) ?? FileNames.default.announcements
        }

        private enum CodingKeys: String, CodingKey {
            case catalogue, bundles, announcements
        }
    }

    let schemaVersion: Int
    let catalogueVersion: Int
    let environment: String
    let publishedAt: Date?
    let minimumAppBuild: Int
    let files: FileNames
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, catalogueVersion, environment, publishedAt, minimumAppBuild, files, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        catalogueVersion = try container.decode(Int.self, forKey: .catalogueVersion)
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? "production"
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        minimumAppBuild = try container.decodeIfPresent(Int.self, forKey: .minimumAppBuild) ?? 1
        files = try container.decodeIfPresent(FileNames.self, forKey: .files) ?? .default
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    init(
        schemaVersion: Int = 1,
        catalogueVersion: Int,
        environment: String = "production",
        publishedAt: Date? = nil,
        minimumAppBuild: Int = 1,
        files: FileNames = .default,
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.catalogueVersion = catalogueVersion
        self.environment = environment
        self.publishedAt = publishedAt
        self.minimumAppBuild = minimumAppBuild
        self.files = files
        self.notes = notes
    }
}
