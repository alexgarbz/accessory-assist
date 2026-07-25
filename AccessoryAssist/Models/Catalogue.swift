import Foundation

/// Decoded contents of `catalogue.json`.
struct Catalogue: Decodable {
    let schemaVersion: Int
    let environment: String
    let generatedAt: Date?
    let currency: String
    let vehicles: [Vehicle]
    let categories: [ProductCategory]
    let products: [Product]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, environment, generatedAt, currency, vehicles, categories, products
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? "production"
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        vehicles = try container.decodeIfPresent([Vehicle].self, forKey: .vehicles) ?? []
        categories = try container.decodeIfPresent([ProductCategory].self, forKey: .categories) ?? []
        products = try container.decode([Product].self, forKey: .products)
    }

    init(
        schemaVersion: Int = 1,
        environment: String = "production",
        generatedAt: Date? = nil,
        currency: String = "USD",
        vehicles: [Vehicle] = [],
        categories: [ProductCategory] = [],
        products: [Product] = []
    ) {
        self.schemaVersion = schemaVersion
        self.environment = environment
        self.generatedAt = generatedAt
        self.currency = currency
        self.vehicles = vehicles
        self.categories = categories
        self.products = products
    }
}

/// Decoded contents of `bundles.json`.
struct BundleCatalogue: Decodable {
    let schemaVersion: Int
    let environment: String
    let bundles: [AccessoryBundle]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, environment, bundles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? "production"
        bundles = try container.decode([AccessoryBundle].self, forKey: .bundles)
    }

    init(schemaVersion: Int = 1, environment: String = "production", bundles: [AccessoryBundle] = []) {
        self.schemaVersion = schemaVersion
        self.environment = environment
        self.bundles = bundles
    }
}

/// Decoded contents of `announcements.json`.
struct AnnouncementFeed: Decodable {
    let schemaVersion: Int
    let announcements: [Announcement]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, announcements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        announcements = try container.decodeIfPresent([Announcement].self, forKey: .announcements) ?? []
    }

    init(schemaVersion: Int = 1, announcements: [Announcement] = []) {
        self.schemaVersion = schemaVersion
        self.announcements = announcements
    }
}

/// Everything the app needs to render, resolved into lookup tables once at load
/// time so that views never perform linear scans while scrolling.
struct CatalogueSnapshot {
    let version: CatalogueVersion
    let catalogue: Catalogue
    let bundleCatalogue: BundleCatalogue
    let announcementFeed: AnnouncementFeed
    /// When these bytes were successfully fetched and accepted.
    let retrievedAt: Date
    /// Which source the bytes came from.
    let source: CatalogueSource
    /// True when the snapshot came from the bundled seed rather than the network.
    let isSeed: Bool

    private let productsById: [String: Product]
    private let categoriesById: [String: ProductCategory]
    private let vehiclesById: [String: Vehicle]

    init(
        version: CatalogueVersion,
        catalogue: Catalogue,
        bundleCatalogue: BundleCatalogue,
        announcementFeed: AnnouncementFeed,
        retrievedAt: Date,
        source: CatalogueSource,
        isSeed: Bool = false
    ) {
        self.version = version
        self.catalogue = catalogue
        self.bundleCatalogue = bundleCatalogue
        self.announcementFeed = announcementFeed
        self.retrievedAt = retrievedAt
        self.source = source
        self.isSeed = isSeed
        productsById = Dictionary(catalogue.products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        categoriesById = Dictionary(catalogue.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        vehiclesById = Dictionary(catalogue.vehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Lookups

    var currency: String { catalogue.currency }

    var sellableProducts: [Product] {
        catalogue.products.filter { $0.status.isSellable }
    }

    var featuredProducts: [Product] {
        sellableProducts.filter(\.featured)
    }

    var activeBundles: [AccessoryBundle] {
        bundleCatalogue.bundles.filter { $0.status.isSellable }
    }

    var featuredBundles: [AccessoryBundle] {
        activeBundles.filter(\.featured)
    }

    var sortedVehicles: [Vehicle] {
        catalogue.vehicles.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    /// Vehicles a user can filter by — the universal catch-all is not a filter
    /// choice, it is how a product declares it fits everything.
    var selectableVehicles: [Vehicle] {
        sortedVehicles.filter { !$0.isUniversal }
    }

    var sortedCategories: [ProductCategory] {
        catalogue.categories.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    func product(id: String) -> Product? { productsById[id] }

    func products(ids: [String]) -> [Product] { ids.compactMap { productsById[$0] } }

    func category(id: String) -> ProductCategory? { categoriesById[id] }

    func categoryName(id: String) -> String { categoriesById[id]?.name ?? id }

    func vehicle(id: String) -> Vehicle? { vehiclesById[id] }

    func bundle(id: String) -> AccessoryBundle? {
        bundleCatalogue.bundles.first { $0.id == id }
    }

    /// Human-readable compatibility summary for a product row.
    func compatibilityLabel(for product: Product) -> String {
        if product.compatibleVehicles.contains(Vehicle.universalId) || product.compatibleVehicles.isEmpty {
            return "All vehicles"
        }
        let names = product.compatibleVehicles.compactMap { vehiclesById[$0]?.name }
        return names.isEmpty ? "All vehicles" : names.joined(separator: ", ")
    }

    /// Announcements that are live at the given moment, pinned first.
    func liveAnnouncements(at date: Date = Date()) -> [Announcement] {
        announcementFeed.announcements
            .filter { $0.isLive(at: date) }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.severity.priority > rhs.severity.priority
            }
    }

    /// Total value of a bundle if its products were bought individually.
    func listPrice(of bundle: AccessoryBundle) -> Decimal {
        products(ids: bundle.productIds).reduce(Decimal.zero) { $0 + $1.price }
    }

    func saving(on bundle: AccessoryBundle) -> Decimal {
        max(listPrice(of: bundle) - bundle.bundlePrice, .zero)
    }
}
