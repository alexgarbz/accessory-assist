import XCTest
@testable import AccessoryAssist

/// Catalogue decoding tests.
///
/// These cover the contract between the content files and the app: field
/// mapping, defaults for optional fields, date handling, and the tolerance
/// rules that stop an older build breaking when the schema gains a value it
/// has never seen.
final class CatalogueDecodingTests: XCTestCase {

    // MARK: - version.json

    func testDecodesVersion() throws {
        let version = try SampleCatalogue.decodedVersion()

        XCTAssertEqual(version.schemaVersion, 1)
        XCTAssertEqual(version.catalogueVersion, 12)
        XCTAssertEqual(version.environment, "production")
        XCTAssertEqual(version.minimumAppBuild, 1)
        XCTAssertEqual(version.files.catalogue, "catalogue.json")
        XCTAssertEqual(version.files.bundles, "bundles.json")
        XCTAssertEqual(version.files.announcements, "announcements.json")
        XCTAssertEqual(version.notes, "Q3 delivery kit pricing.")

        let published = try XCTUnwrap(version.publishedAt)
        XCTAssertEqual(
            ISO8601DateFormatter.catalogueStandard.string(from: published),
            "2026-07-20T09:00:00Z"
        )
    }

    func testVersionFallsBackToDefaultFileNames() throws {
        let json = """
        { "catalogueVersion": 3 }
        """
        let version = try SampleCatalogue.decoder.decode(
            CatalogueVersion.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(version.catalogueVersion, 3)
        XCTAssertEqual(version.schemaVersion, 1)
        XCTAssertEqual(version.files.catalogue, "catalogue.json")
        XCTAssertEqual(version.environment, "production")
        XCTAssertNil(version.publishedAt)
    }

    func testVersionWithoutCatalogueVersionFails() {
        let json = #"{ "schemaVersion": 1 }"#
        XCTAssertThrowsError(
            try SampleCatalogue.decoder.decode(CatalogueVersion.self, from: Data(json.utf8))
        )
    }

    // MARK: - catalogue.json

    func testDecodesCatalogueTaxonomy() throws {
        let catalogue = try SampleCatalogue.decodedCatalogue()

        XCTAssertEqual(catalogue.currency, "USD")
        XCTAssertEqual(catalogue.vehicles.count, 3)
        XCTAssertEqual(catalogue.categories.count, 2)
        XCTAssertEqual(catalogue.products.count, 3)
        XCTAssertEqual(catalogue.vehicles.first?.id, "model_3")
        XCTAssertEqual(catalogue.categories.first?.name, "Interior")
    }

    func testDecodesProductFieldsIncludingRenamedDescription() throws {
        let catalogue = try SampleCatalogue.decodedCatalogue()
        let product = try XCTUnwrap(catalogue.products.first { $0.id == "p_my_int_liners" })

        XCTAssertEqual(product.sku, "TSL-MY-INT-0142")
        XCTAssertEqual(product.name, "Model Y All-Weather Interior Liners")
        XCTAssertEqual(product.summary, "Front, rear and trunk liners.")
        // `description` in JSON maps to `detail` in Swift.
        XCTAssertEqual(product.detail, "Laser-measured thermoplastic liners.")
        XCTAssertEqual(product.price, Decimal(string: "235.00"))
        XCTAssertEqual(product.categoryId, "interior")
        XCTAssertEqual(product.compatibleVehicles, ["model_y"])
        XCTAssertEqual(
            product.imageURL,
            URL(string: "https://images.example.com/liners/2048569-RH-A_1.png")
        )
        // An absolute URL is used verbatim; the cache key is derived from the
        // product id so two products cannot collide on a shared file name.
        XCTAssertEqual(product.imageRef.absoluteURL, product.imageURL)
        XCTAssertEqual(product.imageRef.cacheKey, "p_my_int_liners.png")
        XCTAssertEqual(product.status, .active)
        XCTAssertTrue(product.featured)
        XCTAssertEqual(product.fitNotes, "Fits 5-seat and 7-seat configurations.")
        XCTAssertEqual(product.tags, ["liners", "floor mats"])
    }

    func testOptionalProductFieldsDefaultSafely() throws {
        let catalogue = try SampleCatalogue.decodedCatalogue()
        let product = try XCTUnwrap(catalogue.products.first { $0.id == "p_un_chg_mobile_conn" })

        XCTAssertEqual(product.summary, "")
        XCTAssertEqual(product.detail, "")
        XCTAssertFalse(product.featured)
        XCTAssertNil(product.fitNotes)
        XCTAssertTrue(product.tags.isEmpty)
    }

    func testDecimalPriceKeepsExactValue() throws {
        let catalogue = try SampleCatalogue.decodedCatalogue()
        let product = try XCTUnwrap(catalogue.products.first { $0.id == "p_un_chg_mobile_conn" })

        // Decimal, not Double: 230.50 must stay 230.50 through arithmetic.
        XCTAssertEqual(product.price, Decimal(string: "230.50"))
        XCTAssertEqual(product.price * 3, Decimal(string: "691.50"))
    }

    func testUnknownProductStatusDecodesAsUnknownRatherThanFailing() throws {
        let json = """
        {
          "products": [
            {
              "id": "p_new",
              "sku": "TSL-UN-NEW-0001",
              "name": "Future Product",
              "price": 10,
              "categoryId": "interior",
              "compatibleVehicles": ["universal"],
              "imageName": "p_new.png",
              "status": "preorder_only"
            }
          ]
        }
        """
        let catalogue = try SampleCatalogue.decoder.decode(Catalogue.self, from: Data(json.utf8))

        // An older build must keep working when a future publish adds a status.
        XCTAssertEqual(catalogue.products.first?.status, .unknown)
        XCTAssertFalse(try XCTUnwrap(catalogue.products.first).status.isSellable)
    }

    func testMalformedCatalogueThrows() {
        let json = #"{ "products": [ { "id": "p1" } ] }"#
        XCTAssertThrowsError(
            try SampleCatalogue.decoder.decode(Catalogue.self, from: Data(json.utf8))
        )
    }

    func testInvalidTimestampThrows() {
        let json = #"{ "catalogueVersion": 1, "publishedAt": "20 July 2026" }"#
        XCTAssertThrowsError(
            try SampleCatalogue.decoder.decode(CatalogueVersion.self, from: Data(json.utf8))
        )
    }

    func testFractionalSecondsTimestampDecodes() throws {
        let json = #"{ "catalogueVersion": 1, "publishedAt": "2026-07-20T09:00:00.250Z" }"#
        let version = try SampleCatalogue.decoder.decode(CatalogueVersion.self, from: Data(json.utf8))
        XCTAssertNotNil(version.publishedAt)
    }

    // MARK: - bundles.json

    func testDecodesBundles() throws {
        let bundles = try SampleCatalogue.decodedBundles()
        let bundle = try XCTUnwrap(bundles.bundles.first)

        XCTAssertEqual(bundle.id, "b_delivery_my")
        XCTAssertEqual(bundle.productIds, ["p_my_int_liners", "p_un_chg_mobile_conn"])
        XCTAssertEqual(bundle.bundlePrice, Decimal(string: "420.00"))
        XCTAssertEqual(bundle.detail, "Liners and charging.")
        XCTAssertTrue(bundle.featured)
        XCTAssertEqual(bundle.status, .active)
    }

    // MARK: - announcements.json

    func testDecodesAnnouncementsAndSeverity() throws {
        let feed = try SampleCatalogue.decodedAnnouncements()

        XCTAssertEqual(feed.announcements.count, 2)
        XCTAssertEqual(feed.announcements.first?.severity, .warning)
        XCTAssertTrue(try XCTUnwrap(feed.announcements.first).pinned)
    }

    func testUnknownSeverityFallsBackToInfo() throws {
        let json = """
        { "announcements": [ { "id": "a1", "title": "Note", "severity": "catastrophic" } ] }
        """
        let feed = try SampleCatalogue.decoder.decode(AnnouncementFeed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.announcements.first?.severity, .info)
    }

    // MARK: - Snapshot behaviour

    func testSnapshotBuildsLookupsAndFiltersStatus() throws {
        let snapshot = try SampleCatalogue.snapshot()

        XCTAssertEqual(snapshot.catalogue.products.count, 3)
        XCTAssertEqual(snapshot.sellableProducts.count, 2, "Discontinued products are not sellable")
        XCTAssertEqual(snapshot.featuredProducts.map(\.id), ["p_my_int_liners"])
        XCTAssertNotNil(snapshot.product(id: "p_my_int_liners"))
        XCTAssertNil(snapshot.product(id: "does_not_exist"))
        XCTAssertEqual(snapshot.categoryName(id: "charging"), "Charging")
        XCTAssertEqual(snapshot.vehicle(id: "model_y")?.name, "Model Y")
    }

    func testSelectableVehiclesExcludeUniversal() throws {
        let snapshot = try SampleCatalogue.snapshot()
        XCTAssertEqual(snapshot.selectableVehicles.map(\.id), ["model_3", "model_y"])
        XCTAssertEqual(snapshot.sortedVehicles.count, 3)
    }

    func testCompatibilityLabelUsesVehicleNames() throws {
        let snapshot = try SampleCatalogue.snapshot()
        let liners = try XCTUnwrap(snapshot.product(id: "p_my_int_liners"))
        let connector = try XCTUnwrap(snapshot.product(id: "p_un_chg_mobile_conn"))

        XCTAssertEqual(snapshot.compatibilityLabel(for: liners), "Model Y")
        XCTAssertEqual(snapshot.compatibilityLabel(for: connector), "All vehicles")
    }

    func testUniversalProductFitsEveryVehicle() throws {
        let snapshot = try SampleCatalogue.snapshot()
        let connector = try XCTUnwrap(snapshot.product(id: "p_un_chg_mobile_conn"))
        let liners = try XCTUnwrap(snapshot.product(id: "p_my_int_liners"))

        XCTAssertTrue(connector.fits(vehicleId: "model_3"))
        XCTAssertTrue(connector.fits(vehicleId: "model_y"))
        XCTAssertTrue(connector.fits(vehicleId: nil))
        XCTAssertTrue(liners.fits(vehicleId: "model_y"))
        XCTAssertFalse(liners.fits(vehicleId: "model_3"))
    }

    func testBundlePricingMaths() throws {
        let snapshot = try SampleCatalogue.snapshot()
        let bundle = try XCTUnwrap(snapshot.bundle(id: "b_delivery_my"))

        // 235.00 + 230.50 = 465.50, bundle price 420.00 → saves 45.50
        XCTAssertEqual(snapshot.listPrice(of: bundle), Decimal(string: "465.50"))
        XCTAssertEqual(snapshot.saving(on: bundle), Decimal(string: "45.50"))
    }

    func testLiveAnnouncementsRespectDateWindow() throws {
        let snapshot = try SampleCatalogue.snapshot()
        let insideWindow = ISO8601DateFormatter.catalogueStandard.date(from: "2026-08-01T12:00:00Z")!
        let afterWindow = ISO8601DateFormatter.catalogueStandard.date(from: "2027-01-01T12:00:00Z")!

        XCTAssertEqual(snapshot.liveAnnouncements(at: insideWindow).map(\.id), ["a_pinned"])
        XCTAssertTrue(snapshot.liveAnnouncements(at: afterWindow).isEmpty)
    }

    func testProductSearchMatchesNameSKUAndTags() throws {
        let snapshot = try SampleCatalogue.snapshot()
        let liners = try XCTUnwrap(snapshot.product(id: "p_my_int_liners"))

        XCTAssertTrue(liners.matches(query: "liners"))
        XCTAssertTrue(liners.matches(query: "TSL-MY-INT-0142"))
        XCTAssertTrue(liners.matches(query: "int-0142"))
        XCTAssertTrue(liners.matches(query: "floor mats"))
        XCTAssertTrue(liners.matches(query: "  "), "Blank query matches everything")
        XCTAssertFalse(liners.matches(query: "cybertruck"))
    }

    // MARK: - Seed catalogue shipped with the app

    func testSeedCatalogueInAppBundleDecodes() throws {
        let snapshot = try XCTUnwrap(
            SeedCatalogue.load(),
            "The app bundle must contain a decodable seed catalogue"
        )

        XCTAssertTrue(snapshot.isSeed)
        XCTAssertFalse(snapshot.catalogue.products.isEmpty)
        XCTAssertFalse(snapshot.bundleCatalogue.bundles.isEmpty)
        XCTAssertGreaterThan(snapshot.version.catalogueVersion, 0)

        // The seed must itself be valid content, or a first launch with no
        // network would show something the app would otherwise reject.
        let result = CatalogueValidator.validate(
            version: snapshot.version,
            catalogue: snapshot.catalogue,
            bundles: snapshot.bundleCatalogue,
            announcements: snapshot.announcementFeed
        )
        XCTAssertTrue(result.isAcceptable, "Seed catalogue is invalid: \(result.errors)")
    }
}
