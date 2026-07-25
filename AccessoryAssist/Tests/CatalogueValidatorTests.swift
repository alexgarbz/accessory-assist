import XCTest
@testable import AccessoryAssist

/// Validation tests.
///
/// Each rule in the brief gets a test that proves bad content is rejected —
/// and, just as importantly, that good content is not.
final class CatalogueValidatorTests: XCTestCase {

    private func validate(
        catalogue: Catalogue,
        bundles: BundleCatalogue = BundleCatalogue(),
        announcements: AnnouncementFeed = AnnouncementFeed(),
        version: CatalogueVersion = CatalogueVersion(catalogueVersion: 1),
        images: Set<String>? = nil
    ) -> CatalogueValidator.Result {
        CatalogueValidator.validate(
            version: version,
            catalogue: catalogue,
            bundles: bundles,
            announcements: announcements,
            knownImageNames: images
        )
    }

    private func makeCatalogue(products: [Product]) -> Catalogue {
        Catalogue(
            vehicles: [
                Vehicle(id: "model_y", name: "Model Y"),
                Vehicle(id: "universal", name: "All Vehicles")
            ],
            categories: [ProductCategory(id: "interior", name: "Interior")],
            products: products
        )
    }

    private func makeProduct(
        id: String = "p_1",
        sku: String = "TSL-MY-INT-0142",
        price: Decimal = 235,
        categoryId: String = "interior",
        vehicles: [String] = ["model_y"],
        imageName: String = "p_1.png",
        status: ProductStatus = .active,
        name: String = "Liners"
    ) -> Product {
        Product(
            id: id,
            sku: sku,
            name: name,
            price: price,
            categoryId: categoryId,
            compatibleVehicles: vehicles,
            imageName: imageName,
            status: status
        )
    }

    // MARK: - Happy path

    func testValidCataloguePasses() throws {
        let result = CatalogueValidator.validate(
            version: try SampleCatalogue.decodedVersion(),
            catalogue: try SampleCatalogue.decodedCatalogue(),
            bundles: try SampleCatalogue.decodedBundles(),
            announcements: try SampleCatalogue.decodedAnnouncements()
        )

        XCTAssertTrue(result.isAcceptable, "Unexpected errors: \(result.errors)")
        XCTAssertTrue(result.errors.isEmpty)
    }

    // MARK: - Product ids and SKUs

    func testDuplicateProductIdIsRejected() {
        let catalogue = makeCatalogue(products: [
            makeProduct(id: "p_1", sku: "TSL-MY-INT-0001"),
            makeProduct(id: "p_1", sku: "TSL-MY-INT-0002")
        ])
        let result = validate(catalogue: catalogue)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("Duplicate product id") })
    }

    func testDuplicateSKUIsRejected() {
        let catalogue = makeCatalogue(products: [
            makeProduct(id: "p_1", sku: "TSL-MY-INT-0142"),
            makeProduct(id: "p_2", sku: "TSL-MY-INT-0142")
        ])
        let result = validate(catalogue: catalogue)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("Duplicate SKU") })
    }

    func testMalformedSKUIsRejected() {
        for badSKU in ["tsl-my-int-0142", "TSL_MY_INT", "TSL", "", "TSL-MY-INT-0142-EXTRA-TOO-LONG"] {
            let catalogue = makeCatalogue(products: [makeProduct(sku: badSKU)])
            let result = validate(catalogue: catalogue)
            XCTAssertFalse(result.isAcceptable, "SKU \"\(badSKU)\" should be rejected")
        }
    }

    func testWellFormedSKUIsAccepted() {
        for goodSKU in ["TSL-MY-INT-0142", "TS-M3-001", "TSL-UN-CHG-0301"] {
            let catalogue = makeCatalogue(products: [makeProduct(sku: goodSKU)])
            let result = validate(catalogue: catalogue)
            XCTAssertTrue(result.isAcceptable, "SKU \"\(goodSKU)\" should be accepted: \(result.errors)")
        }
    }

    func testRealTeslaPartNumbersAreAccepted() {
        // Part numbers as printed on the item. The letter-coded middle group
        // (RH, TS, WL, FT) is used across the all-weather liner range.
        for partNumber in [
            "1529454-42-H",
            "1479094-00-B",
            "2048569-RH-A",
            "2048569-WL-A",
            "1819445-70-B",
            "1859203-00-C"
        ] {
            let catalogue = makeCatalogue(products: [makeProduct(sku: partNumber)])
            let result = validate(catalogue: catalogue)
            XCTAssertTrue(
                result.isAcceptable,
                "Part number \"\(partNumber)\" should be accepted: \(result.errors)"
            )
            XCTAssertTrue(Code128.canEncode(partNumber))
        }
    }

    func testEmptyProductNameIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(name: "  ")])
        XCTAssertFalse(validate(catalogue: catalogue).isAcceptable)
    }

    // MARK: - Prices

    func testNegativePriceIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(price: -1)])
        let result = validate(catalogue: catalogue)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("negative") })
    }

    func testZeroPriceOnActiveProductIsAWarningNotAnError() {
        let catalogue = makeCatalogue(products: [makeProduct(price: 0)])
        let result = validate(catalogue: catalogue)

        XCTAssertTrue(result.isAcceptable)
        XCTAssertEqual(result.warnings.count, 1)
    }

    // MARK: - Taxonomy references

    func testUnknownVehicleIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(vehicles: ["model_z"])])
        let result = validate(catalogue: catalogue)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("Unknown vehicle") })
    }

    func testEmptyVehicleListIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(vehicles: [])])
        XCTAssertFalse(validate(catalogue: catalogue).isAcceptable)
    }

    func testUnknownCategoryIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(categoryId: "nonexistent")])
        let result = validate(catalogue: catalogue)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("Unknown category") })
    }

    func testCatalogueWithoutVehiclesOrCategoriesIsRejected() {
        let catalogue = Catalogue(products: [makeProduct()])
        XCTAssertFalse(validate(catalogue: catalogue).isAcceptable)
    }

    // MARK: - Images

    func testEmptyImageNameIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(imageName: "")])
        XCTAssertFalse(validate(catalogue: catalogue).isAcceptable)
    }

    func testUnsupportedImageTypeIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(imageName: "liners.tiff")])
        XCTAssertFalse(validate(catalogue: catalogue).isAcceptable)
    }

    func testImagePathTraversalIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(imageName: "../secrets/liners.png")])
        XCTAssertFalse(validate(catalogue: catalogue).isAcceptable)
    }

    func testMissingImageIsRejectedWhenTheImageListIsKnown() {
        let catalogue = makeCatalogue(products: [makeProduct(imageName: "not_published.png")])
        let result = validate(catalogue: catalogue, images: ["p_1.png"])

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("is not present") })
    }

    func testPresentImagePasses() {
        let catalogue = makeCatalogue(products: [makeProduct(imageName: "p_1.png")])
        XCTAssertTrue(validate(catalogue: catalogue, images: ["p_1.png"]).isAcceptable)
    }

    // MARK: - Bundles

    func testBundleReferencingUnknownProductIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(id: "p_1")])
        let bundles = BundleCatalogue(bundles: [
            AccessoryBundle(
                id: "b_1",
                name: "Kit",
                productIds: ["p_1", "p_missing"],
                bundlePrice: 100,
                imageName: "b_1.png"
            )
        ])
        let result = validate(catalogue: catalogue, bundles: bundles)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("unknown product") })
    }

    func testActiveBundleReferencingDiscontinuedProductIsRejected() {
        let catalogue = makeCatalogue(products: [
            makeProduct(id: "p_1", sku: "TSL-MY-INT-0001"),
            makeProduct(id: "p_2", sku: "TSL-MY-INT-0002", status: .discontinued)
        ])
        let bundles = BundleCatalogue(bundles: [
            AccessoryBundle(id: "b_1", name: "Kit", productIds: ["p_1", "p_2"], bundlePrice: 100, imageName: "b_1.png")
        ])

        XCTAssertFalse(validate(catalogue: catalogue, bundles: bundles).isAcceptable)
    }

    func testEmptyBundleIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct()])
        let bundles = BundleCatalogue(bundles: [
            AccessoryBundle(id: "b_1", name: "Kit", productIds: [], bundlePrice: 100, imageName: "b_1.png")
        ])

        XCTAssertFalse(validate(catalogue: catalogue, bundles: bundles).isAcceptable)
    }

    func testDuplicateBundleIdIsRejected() {
        let catalogue = makeCatalogue(products: [makeProduct(id: "p_1")])
        let bundles = BundleCatalogue(bundles: [
            AccessoryBundle(id: "b_1", name: "Kit", productIds: ["p_1"], bundlePrice: 100, imageName: "b_1.png"),
            AccessoryBundle(id: "b_1", name: "Kit 2", productIds: ["p_1"], bundlePrice: 120, imageName: "b_1.png")
        ])

        XCTAssertFalse(validate(catalogue: catalogue, bundles: bundles).isAcceptable)
    }

    func testBundlePricedAboveItsContentsIsAWarning() {
        let catalogue = makeCatalogue(products: [makeProduct(id: "p_1", price: 100)])
        let bundles = BundleCatalogue(bundles: [
            AccessoryBundle(id: "b_1", name: "Kit", productIds: ["p_1"], bundlePrice: 150, imageName: "b_1.png")
        ])
        let result = validate(catalogue: catalogue, bundles: bundles)

        XCTAssertTrue(result.isAcceptable)
        XCTAssertTrue(result.warnings.contains { $0.message.contains("exceeds the sum") })
    }

    // MARK: - Announcements

    func testAnnouncementEndingBeforeItStartsIsRejected() {
        let feed = AnnouncementFeed(announcements: [
            Announcement(
                id: "a_1",
                title: "Backwards",
                startsAt: Date(timeIntervalSince1970: 2000),
                endsAt: Date(timeIntervalSince1970: 1000)
            )
        ])
        let result = validate(catalogue: makeCatalogue(products: [makeProduct()]), announcements: feed)

        XCTAssertFalse(result.isAcceptable)
    }

    // MARK: - Schema

    func testNewerSchemaVersionIsRejected() {
        let version = CatalogueVersion(schemaVersion: 99, catalogueVersion: 5)
        let result = validate(catalogue: makeCatalogue(products: [makeProduct()]), version: version)

        XCTAssertFalse(result.isAcceptable)
        XCTAssertTrue(result.errors.contains { $0.message.contains("newer than this app supports") })
    }

    func testUnknownProductStatusIsRejectedByValidation() {
        let json = """
        {
          "vehicles": [{ "id": "universal", "name": "All" }],
          "categories": [{ "id": "interior", "name": "Interior" }],
          "products": [{
            "id": "p_1", "sku": "TSL-UN-INT-0001", "name": "Thing", "price": 10,
            "categoryId": "interior", "compatibleVehicles": ["universal"],
            "imageName": "p_1.png", "status": "made_up"
          }]
        }
        """
        let catalogue = try! SampleCatalogue.decoder.decode(Catalogue.self, from: Data(json.utf8))
        let result = validate(catalogue: catalogue)

        // Decoding tolerates it; publishing does not.
        XCTAssertEqual(catalogue.products.first?.status, .unknown)
        XCTAssertFalse(result.isAcceptable)
    }
}
