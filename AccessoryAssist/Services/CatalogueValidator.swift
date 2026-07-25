import Foundation

/// Structural validation applied to freshly downloaded catalogue content
/// *before* it is allowed to replace the working local copy.
///
/// The same rules are implemented in `scripts/validate_catalogue.py`, which
/// runs in CI on every change to `remote-data/`. Content that fails in CI never
/// reaches a device; content that somehow does is rejected here and the
/// previous good catalogue is retained.
enum CatalogueValidator {

    struct Issue: Equatable, Identifiable, CustomStringConvertible {
        enum Severity: String, Equatable {
            case error
            case warning
        }

        let severity: Severity
        /// Where the problem is, e.g. `products[4]` or `bundles.b_winter_my`.
        let path: String
        let message: String

        var id: String { "\(severity.rawValue)|\(path)|\(message)" }
        var description: String { "[\(severity.rawValue)] \(path): \(message)" }
    }

    struct Result: Equatable {
        let issues: [Issue]

        var errors: [Issue] { issues.filter { $0.severity == .error } }
        var warnings: [Issue] { issues.filter { $0.severity == .warning } }
        var isAcceptable: Bool { errors.isEmpty }
    }

    /// SKUs are uppercase alphanumeric groups separated by hyphens, e.g.
    /// `TSL-MY-INT-0142`. Kept strict so barcodes stay short and scannable.
    static let skuPattern = "^[A-Z0-9]{2,5}(-[A-Z0-9]{1,6}){1,4}$"

    /// Image file extensions the app knows how to decode.
    static let allowedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]

    // MARK: - Entry point

    /// Validate a decoded catalogue set.
    ///
    /// - Parameter knownImageNames: image file names known to exist at the
    ///   source. Pass `nil` on device, where the app cannot enumerate remote
    ///   storage — CI performs the authoritative existence check.
    static func validate(
        version: CatalogueVersion,
        catalogue: Catalogue,
        bundles: BundleCatalogue,
        announcements: AnnouncementFeed,
        knownImageNames: Set<String>? = nil
    ) -> Result {
        var issues: [Issue] = []

        issues += validateVersion(version)
        issues += validateTaxonomy(catalogue)
        issues += validateProducts(catalogue, knownImageNames: knownImageNames)
        issues += validateBundles(bundles, catalogue: catalogue, knownImageNames: knownImageNames)
        issues += validateAnnouncements(announcements)

        return Result(issues: issues)
    }

    // MARK: - Rules

    private static func validateVersion(_ version: CatalogueVersion) -> [Issue] {
        var issues: [Issue] = []
        if version.catalogueVersion < 0 {
            issues.append(Issue(severity: .error, path: "version.catalogueVersion",
                                message: "Catalogue version must not be negative."))
        }
        if version.schemaVersion > Self.supportedSchemaVersion {
            issues.append(Issue(severity: .error, path: "version.schemaVersion",
                                message: "Schema version \(version.schemaVersion) is newer than this app supports (\(Self.supportedSchemaVersion)). Update the app."))
        }
        return issues
    }

    static let supportedSchemaVersion = 1

    private static func validateTaxonomy(_ catalogue: Catalogue) -> [Issue] {
        var issues: [Issue] = []

        if catalogue.vehicles.isEmpty {
            issues.append(Issue(severity: .error, path: "catalogue.vehicles",
                                message: "At least one vehicle must be published."))
        }
        if catalogue.categories.isEmpty {
            issues.append(Issue(severity: .error, path: "catalogue.categories",
                                message: "At least one category must be published."))
        }

        var seenVehicles: Set<String> = []
        for vehicle in catalogue.vehicles where !seenVehicles.insert(vehicle.id).inserted {
            issues.append(Issue(severity: .error, path: "catalogue.vehicles.\(vehicle.id)",
                                message: "Duplicate vehicle id."))
        }

        var seenCategories: Set<String> = []
        for category in catalogue.categories where !seenCategories.insert(category.id).inserted {
            issues.append(Issue(severity: .error, path: "catalogue.categories.\(category.id)",
                                message: "Duplicate category id."))
        }

        if catalogue.products.isEmpty {
            issues.append(Issue(severity: .error, path: "catalogue.products",
                                message: "Catalogue contains no products."))
        }

        return issues
    }

    private static func validateProducts(
        _ catalogue: Catalogue,
        knownImageNames: Set<String>?
    ) -> [Issue] {
        var issues: [Issue] = []
        let vehicleIds = Set(catalogue.vehicles.map(\.id))
        let categoryIds = Set(catalogue.categories.map(\.id))

        var seenIds: Set<String> = []
        var seenSKUs: [String: String] = [:]  // sku -> first product id

        for (index, product) in catalogue.products.enumerated() {
            let path = "products[\(index)] \(product.id)"

            // Unique id
            if product.id.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(Issue(severity: .error, path: path, message: "Product id is empty."))
            } else if !seenIds.insert(product.id).inserted {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Duplicate product id \"\(product.id)\"."))
            }

            // Valid, unique SKU
            if product.sku.isEmpty {
                issues.append(Issue(severity: .error, path: path, message: "SKU is empty."))
            } else {
                if product.sku.range(of: skuPattern, options: .regularExpression) == nil {
                    issues.append(Issue(severity: .error, path: path,
                                        message: "SKU \"\(product.sku)\" does not match the required format."))
                }
                if !Code128.canEncode(product.sku) {
                    issues.append(Issue(severity: .error, path: path,
                                        message: "SKU \"\(product.sku)\" cannot be encoded as a Code 128 barcode."))
                }
                if let existing = seenSKUs[product.sku] {
                    issues.append(Issue(severity: .error, path: path,
                                        message: "Duplicate SKU \"\(product.sku)\", already used by \"\(existing)\"."))
                } else {
                    seenSKUs[product.sku] = product.id
                }
            }

            if product.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(Issue(severity: .error, path: path, message: "Product name is empty."))
            }

            // Price
            if product.price < 0 {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Price must not be negative."))
            } else if product.price == 0 && product.status.isSellable {
                issues.append(Issue(severity: .warning, path: path,
                                    message: "Active product is priced at zero."))
            }

            // Category
            if !categoryIds.contains(product.categoryId) {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Unknown category \"\(product.categoryId)\"."))
            }

            // Vehicle compatibility must come from the published list
            if product.compatibleVehicles.isEmpty {
                issues.append(Issue(severity: .error, path: path,
                                    message: "No compatible vehicles listed. Use \"\(Vehicle.universalId)\" for fit-all accessories."))
            }
            for vehicleId in product.compatibleVehicles where !vehicleIds.contains(vehicleId) {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Unknown vehicle \"\(vehicleId)\"."))
            }

            // Status
            if product.status == .unknown {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Unrecognised product status."))
            }

            issues += validateImage(product.imageName, path: path, knownImageNames: knownImageNames)
        }

        return issues
    }

    private static func validateBundles(
        _ bundles: BundleCatalogue,
        catalogue: Catalogue,
        knownImageNames: Set<String>?
    ) -> [Issue] {
        var issues: [Issue] = []
        let productsById = Dictionary(catalogue.products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let vehicleIds = Set(catalogue.vehicles.map(\.id))
        var seenIds: Set<String> = []

        for (index, bundle) in bundles.bundles.enumerated() {
            let path = "bundles[\(index)] \(bundle.id)"

            if !seenIds.insert(bundle.id).inserted {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Duplicate bundle id \"\(bundle.id)\"."))
            }

            if bundle.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(Issue(severity: .error, path: path, message: "Bundle name is empty."))
            }

            if bundle.productIds.isEmpty {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Bundle contains no products."))
            }

            for productId in bundle.productIds {
                guard let product = productsById[productId] else {
                    issues.append(Issue(severity: .error, path: path,
                                        message: "References unknown product \"\(productId)\"."))
                    continue
                }
                if bundle.status.isSellable && !product.status.isSellable {
                    issues.append(Issue(severity: .error, path: path,
                                        message: "Active bundle references \(product.status.label.lowercased()) product \"\(productId)\"."))
                }
            }

            if bundle.bundlePrice < 0 {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Bundle price must not be negative."))
            }

            let listPrice = bundle.productIds
                .compactMap { productsById[$0]?.price }
                .reduce(Decimal.zero, +)
            if bundle.bundlePrice > listPrice && listPrice > 0 {
                issues.append(Issue(severity: .warning, path: path,
                                    message: "Bundle price exceeds the sum of its products."))
            }

            for vehicleId in bundle.compatibleVehicles where !vehicleIds.contains(vehicleId) {
                issues.append(Issue(severity: .error, path: path,
                                    message: "Unknown vehicle \"\(vehicleId)\"."))
            }

            issues += validateImage(bundle.imageName, path: path, knownImageNames: knownImageNames)
        }

        return issues
    }

    private static func validateAnnouncements(_ feed: AnnouncementFeed) -> [Issue] {
        var issues: [Issue] = []
        var seenIds: Set<String> = []
        for (index, announcement) in feed.announcements.enumerated() {
            let path = "announcements[\(index)] \(announcement.id)"
            if !seenIds.insert(announcement.id).inserted {
                issues.append(Issue(severity: .error, path: path, message: "Duplicate announcement id."))
            }
            if announcement.title.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(Issue(severity: .error, path: path, message: "Announcement title is empty."))
            }
            if let start = announcement.startsAt, let end = announcement.endsAt, end < start {
                issues.append(Issue(severity: .error, path: path, message: "Announcement ends before it starts."))
            }
        }
        return issues
    }

    private static func validateImage(
        _ imageName: String,
        path: String,
        knownImageNames: Set<String>?
    ) -> [Issue] {
        var issues: [Issue] = []
        if imageName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(Issue(severity: .error, path: path, message: "Image file name is empty."))
            return issues
        }
        let ext = (imageName as NSString).pathExtension.lowercased()
        if !allowedImageExtensions.contains(ext) {
            issues.append(Issue(severity: .error, path: path,
                                message: "Image \"\(imageName)\" uses an unsupported file type."))
        }
        if imageName.contains("/") || imageName.contains("..") {
            issues.append(Issue(severity: .error, path: path,
                                message: "Image name must be a bare file name in the images directory."))
        }
        if let knownImageNames, !knownImageNames.contains(imageName) {
            issues.append(Issue(severity: .error, path: path,
                                message: "Image \"\(imageName)\" is not present in the images directory."))
        }
        return issues
    }
}
