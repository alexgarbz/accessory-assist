import Foundation

/// Lifecycle state of a catalogue product.
///
/// Unknown values decode to `.unknown` rather than failing, so that a future
/// catalogue publish cannot break an older build of the app in the field.
enum ProductStatus: String, Decodable, Hashable {
    case active
    case discontinued
    case upcoming
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProductStatus(rawValue: raw) ?? .unknown
    }

    /// Products that may be sold today.
    var isSellable: Bool { self == .active }

    var label: String {
        switch self {
        case .active: return "Active"
        case .discontinued: return "Discontinued"
        case .upcoming: return "Upcoming"
        case .unknown: return "Unrecognised"
        }
    }
}

struct Product: Decodable, Identifiable, Hashable {
    let id: String
    let sku: String
    let name: String
    let summary: String
    let detail: String
    let price: Decimal
    let categoryId: String
    let compatibleVehicles: [String]
    /// Bare file name served from the catalogue's own `images/` directory.
    let imageName: String
    /// Absolute URL for photography hosted outside the catalogue. Takes
    /// precedence over `imageName` when both are present.
    let imageURL: URL?
    let status: ProductStatus
    let featured: Bool
    let fitNotes: String?
    let tags: [String]

    private enum CodingKeys: String, CodingKey {
        case id, sku, name, summary
        case detail = "description"
        case price, categoryId, compatibleVehicles, imageName, imageURL, status, featured, fitNotes, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sku = try container.decode(String.self, forKey: .sku)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        price = try container.decode(Decimal.self, forKey: .price)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        compatibleVehicles = try container.decodeIfPresent([String].self, forKey: .compatibleVehicles) ?? []
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName) ?? ""
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL).flatMap(URL.init(string:))
        status = try container.decodeIfPresent(ProductStatus.self, forKey: .status) ?? .active
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        fitNotes = try container.decodeIfPresent(String.self, forKey: .fitNotes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// Memberwise initialiser used by previews and tests.
    init(
        id: String,
        sku: String,
        name: String,
        summary: String = "",
        detail: String = "",
        price: Decimal,
        categoryId: String,
        compatibleVehicles: [String] = [],
        imageName: String = "",
        imageURL: URL? = nil,
        status: ProductStatus = .active,
        featured: Bool = false,
        fitNotes: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.summary = summary
        self.detail = detail
        self.price = price
        self.categoryId = categoryId
        self.compatibleVehicles = compatibleVehicles
        self.imageName = imageName
        self.imageURL = imageURL
        self.status = status
        self.featured = featured
        self.fitNotes = fitNotes
        self.tags = tags
    }

    /// Where this product's image comes from.
    var imageRef: CatalogueImageRef {
        CatalogueImageRef(imageName: imageName, imageURL: imageURL, fallbackKey: id)
    }

    /// True when the product fits the given vehicle id, honouring the
    /// `universal` catch-all used for vehicle-agnostic accessories.
    func fits(vehicleId: String?) -> Bool {
        guard let vehicleId, vehicleId != Vehicle.universalId else { return true }
        return compatibleVehicles.contains(vehicleId)
            || compatibleVehicles.contains(Vehicle.universalId)
    }

    /// Free-text match used by the search field. Deliberately narrow: staff
    /// search by name, SKU or tag, never by long-form description.
    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if name.lowercased().contains(needle) { return true }
        if sku.lowercased().contains(needle) { return true }
        if summary.lowercased().contains(needle) { return true }
        return tags.contains { $0.lowercased().contains(needle) }
    }
}
