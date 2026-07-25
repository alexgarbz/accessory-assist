import Foundation
@testable import AccessoryAssist

/// Hermetic fixtures.
///
/// The JSON here is written by hand rather than loaded from `remote-data`, so
/// the decoding tests describe the contract the app depends on and fail loudly
/// if that contract changes — independently of whatever the sample content
/// happens to contain today.
enum SampleCatalogue {

    /// A cross-section of the SKU formats the catalogue actually publishes:
    /// Tesla part numbers as printed on the item, including the letter-coded
    /// variants used by the liner range, alongside the internal scheme used by
    /// the remaining sample content.
    static let skus = [
        // Tesla part numbers
        "1529454-42-H",
        "1479094-00-B",
        "1039810-00-A",
        "2048569-RH-A",
        "2048569-TS-A",
        "2073497-00-A",
        "1819445-70-B",
        "1859203-00-C",
        "2166154-00-A",
        "1934882-00-A",
        // Internal scheme
        "TSL-M3-INT-0138",
        "TSL-MS-INT-0120",
        "TSL-CT-CRG-0220",
        "TSL-MY-WHL-0601"
    ]

    static let versionJSON = """
    {
      "schemaVersion": 1,
      "catalogueVersion": 12,
      "environment": "production",
      "publishedAt": "2026-07-20T09:00:00Z",
      "minimumAppBuild": 1,
      "files": {
        "catalogue": "catalogue.json",
        "bundles": "bundles.json",
        "announcements": "announcements.json"
      },
      "notes": "Q3 delivery kit pricing."
    }
    """

    static let catalogueJSON = """
    {
      "schemaVersion": 1,
      "environment": "production",
      "generatedAt": "2026-07-20T09:00:00Z",
      "currency": "USD",
      "vehicles": [
        { "id": "model_3", "name": "Model 3", "order": 2 },
        { "id": "model_y", "name": "Model Y", "order": 4 },
        { "id": "universal", "name": "All Vehicles", "order": 6 }
      ],
      "categories": [
        { "id": "interior", "name": "Interior", "order": 1 },
        { "id": "charging", "name": "Charging", "order": 3 }
      ],
      "products": [
        {
          "id": "p_my_int_liners",
          "sku": "TSL-MY-INT-0142",
          "name": "Model Y All-Weather Interior Liners",
          "summary": "Front, rear and trunk liners.",
          "description": "Laser-measured thermoplastic liners.",
          "price": 235.00,
          "categoryId": "interior",
          "compatibleVehicles": ["model_y"],
          "imageName": "p_my_int_liners.png",
          "status": "active",
          "featured": true,
          "fitNotes": "Fits 5-seat and 7-seat configurations.",
          "tags": ["liners", "floor mats"]
        },
        {
          "id": "p_un_chg_mobile_conn",
          "sku": "TSL-UN-CHG-0301",
          "name": "Mobile Connector Bundle",
          "price": 230.50,
          "categoryId": "charging",
          "compatibleVehicles": ["universal"],
          "imageName": "p_un_chg_mobile_conn.png",
          "status": "active"
        },
        {
          "id": "p_m3_ext_pedal_set",
          "sku": "TSL-M3-EXT-0420",
          "name": "Model 3 Sport Pedal Set",
          "price": 85.00,
          "categoryId": "interior",
          "compatibleVehicles": ["model_3"],
          "imageName": "p_m3_ext_pedal_set.png",
          "status": "discontinued"
        }
      ]
    }
    """

    static let bundlesJSON = """
    {
      "schemaVersion": 1,
      "environment": "production",
      "bundles": [
        {
          "id": "b_delivery_my",
          "name": "Model Y Delivery Day Kit",
          "summary": "Most commonly added at handover.",
          "description": "Liners and charging.",
          "productIds": ["p_my_int_liners", "p_un_chg_mobile_conn"],
          "bundlePrice": 420.00,
          "imageName": "b_delivery_my.png",
          "compatibleVehicles": ["model_y"],
          "status": "active",
          "featured": true
        }
      ]
    }
    """

    static let announcementsJSON = """
    {
      "schemaVersion": 1,
      "announcements": [
        {
          "id": "a_pinned",
          "title": "Check adapter eligibility",
          "body": "Confirm in the service portal before sale.",
          "severity": "warning",
          "startsAt": "2026-07-01T00:00:00Z",
          "endsAt": "2026-09-30T23:59:59Z",
          "pinned": true
        },
        {
          "id": "a_expired",
          "title": "Old notice",
          "body": "No longer relevant.",
          "severity": "info",
          "startsAt": "2026-01-01T00:00:00Z",
          "endsAt": "2026-02-01T00:00:00Z",
          "pinned": false
        }
      ]
    }
    """

    // MARK: - Helpers

    static var decoder: JSONDecoder { .catalogueDecoder }

    static func decodedVersion() throws -> CatalogueVersion {
        try decoder.decode(CatalogueVersion.self, from: Data(versionJSON.utf8))
    }

    static func decodedCatalogue() throws -> Catalogue {
        try decoder.decode(Catalogue.self, from: Data(catalogueJSON.utf8))
    }

    static func decodedBundles() throws -> BundleCatalogue {
        try decoder.decode(BundleCatalogue.self, from: Data(bundlesJSON.utf8))
    }

    static func decodedAnnouncements() throws -> AnnouncementFeed {
        try decoder.decode(AnnouncementFeed.self, from: Data(announcementsJSON.utf8))
    }

    static func snapshot() throws -> CatalogueSnapshot {
        CatalogueSnapshot(
            version: try decodedVersion(),
            catalogue: try decodedCatalogue(),
            bundleCatalogue: try decodedBundles(),
            announcementFeed: try decodedAnnouncements(),
            retrievedAt: Date(timeIntervalSince1970: 1_780_000_000),
            source: .production
        )
    }
}
