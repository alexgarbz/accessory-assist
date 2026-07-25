import Foundation

/// A merchandised group of products sold at a single bundle price.
///
/// Named `AccessoryBundle` rather than `Bundle` to avoid shadowing
/// `Foundation.Bundle`, which the app uses for seed data loading.
struct AccessoryBundle: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let detail: String
    let productIds: [String]
    let bundlePrice: Decimal
    let imageName: String
    let compatibleVehicles: [String]
    let status: ProductStatus
    let featured: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, summary
        case detail = "description"
        case productIds, bundlePrice, imageName, compatibleVehicles, status, featured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        productIds = try container.decode([String].self, forKey: .productIds)
        bundlePrice = try container.decode(Decimal.self, forKey: .bundlePrice)
        imageName = try container.decode(String.self, forKey: .imageName)
        compatibleVehicles = try container.decodeIfPresent([String].self, forKey: .compatibleVehicles) ?? []
        status = try container.decodeIfPresent(ProductStatus.self, forKey: .status) ?? .active
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
    }

    init(
        id: String,
        name: String,
        summary: String = "",
        detail: String = "",
        productIds: [String],
        bundlePrice: Decimal,
        imageName: String = "",
        compatibleVehicles: [String] = [],
        status: ProductStatus = .active,
        featured: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.detail = detail
        self.productIds = productIds
        self.bundlePrice = bundlePrice
        self.imageName = imageName
        self.compatibleVehicles = compatibleVehicles
        self.status = status
        self.featured = featured
    }

    func fits(vehicleId: String?) -> Bool {
        guard let vehicleId, vehicleId != Vehicle.universalId else { return true }
        return compatibleVehicles.contains(vehicleId)
            || compatibleVehicles.contains(Vehicle.universalId)
            || compatibleVehicles.isEmpty
    }
}
