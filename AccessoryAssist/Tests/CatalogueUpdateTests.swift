import XCTest
@testable import AccessoryAssist

/// Update-flow tests.
///
/// These cover the guarantees the brief asks for, end to end and without a
/// network: check the version first, download only when it changed, validate
/// before replacing, and keep the last working catalogue whenever anything
/// goes wrong.
@MainActor
final class CatalogueUpdateTests: XCTestCase {

    private var source: CatalogueSource!
    private var fetcher: FakeFetcher!

    override func setUp() async throws {
        try await super.setUp()
        // A unique base URL per test gives each one its own cache directory.
        source = .custom(URL(string: "https://catalogue.test/\(UUID().uuidString)/")!)
        fetcher = FakeFetcher()
        fetcher.serve(version: 20, catalogue: FakeFetcher.validCatalogue)
    }

    override func tearDown() async throws {
        CatalogueCacheStore(source: source).clear()
        try await super.tearDown()
    }

    private func makeService() -> CatalogueService {
        CatalogueService(
            source: source,
            fetcher: fetcher,
            imageStore: ImageStore(source: source, fetcher: fetcher)
        )
    }

    // MARK: - Downloading

    func testFirstRefreshDownloadsAndPublishesCatalogue() async {
        let service = makeService()
        await service.refreshAndWait()

        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20)
        XCTAssertEqual(service.snapshot?.catalogue.products.count, 2)
        XCTAssertFalse(service.snapshot?.isSeed ?? true)
        XCTAssertNil(service.lastError)
        XCTAssertNotNil(service.lastSuccessfulUpdate)
        XCTAssertFalse(service.isUsingOfflineData)
    }

    func testVersionIsCheckedBeforeContentIsDownloaded() async {
        let service = makeService()
        await service.refreshAndWait()

        XCTAssertEqual(fetcher.requestedFileNames.first, "version.json",
                       "version.json must be the first request of a refresh")
        XCTAssertTrue(fetcher.requestedFileNames.contains("catalogue.json"))
    }

    func testUnchangedVersionSkipsTheContentDownload() async {
        let service = makeService()
        await service.refreshAndWait()
        fetcher.resetLog()

        await service.refreshAndWait()

        XCTAssertEqual(fetcher.requestedFileNames, ["version.json"],
                       "Only the version probe should be fetched when nothing changed")
        XCTAssertEqual(service.lastOutcome, .upToDate)
        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20)
    }

    func testNewerVersionTriggersDownload() async {
        let service = makeService()
        await service.refreshAndWait()

        fetcher.resetLog()
        fetcher.serve(version: 21, catalogue: FakeFetcher.validCatalogue)
        await service.refreshAndWait()

        XCTAssertTrue(fetcher.requestedFileNames.contains("catalogue.json"))
        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 21)
        XCTAssertEqual(service.lastOutcome, .updated(from: 20, to: 21))
    }

    func testForcedRefreshDownloadsEvenWhenVersionMatches() async {
        let service = makeService()
        await service.refreshAndWait()
        fetcher.resetLog()

        await service.refreshAndWait(force: true)

        XCTAssertTrue(fetcher.requestedFileNames.contains("catalogue.json"),
                      "Manual Refresh Catalogue must re-download regardless of version")
    }

    // MARK: - Rejection keeps the working catalogue

    func testInvalidCatalogueIsRejectedAndPreviousCopyRetained() async {
        let service = makeService()
        await service.refreshAndWait()
        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20)

        // Publish a newer version whose content breaks a validation rule.
        fetcher.serve(version: 21, catalogue: FakeFetcher.duplicateSKUCatalogue)
        await service.refreshAndWait()

        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20,
                       "The working catalogue must survive a rejected publish")
        XCTAssertEqual(service.snapshot?.catalogue.products.count, 2)
        XCTAssertTrue(service.lastValidationIssues.contains { $0.message.contains("Duplicate SKU") })
        guard case .rejected = service.lastError else {
            return XCTFail("Expected a rejection error, got \(String(describing: service.lastError))")
        }
        XCTAssertTrue(service.isUsingOfflineData)
    }

    func testMalformedJSONIsRejectedAndPreviousCopyRetained() async {
        let service = makeService()
        await service.refreshAndWait()

        fetcher.serve(version: 22, catalogue: "{ this is not json")
        await service.refreshAndWait()

        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20)
        XCTAssertEqual(service.lastError, .malformed("catalogue.json"))
    }

    func testMalformedVersionFileIsRejected() async {
        let service = makeService()
        await service.refreshAndWait()

        fetcher.responses["version.json"] = .success(Data("<html>404</html>".utf8))
        await service.refreshAndWait()

        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20)
        XCTAssertEqual(service.lastError, .malformed("version.json"))
    }

    // MARK: - Offline behaviour

    func testNetworkFailureRetainsTheCachedCatalogue() async {
        let service = makeService()
        await service.refreshAndWait()

        fetcher.failEverything(with: .offline)
        await service.refreshAndWait()

        XCTAssertEqual(service.snapshot?.version.catalogueVersion, 20,
                       "Losing the network must not lose the catalogue")
        XCTAssertEqual(service.lastError, .offline)
        XCTAssertTrue(service.isOffline)
        XCTAssertTrue(service.isUsingOfflineData)
        XCTAssertNotNil(service.lastSuccessfulUpdate, "The last good update time is still reported")
    }

    func testUnauthorisedSourceIsReportedDistinctly() async {
        fetcher.failEverything(with: .unauthorised)
        let service = makeService()
        await service.refreshAndWait()

        XCTAssertEqual(service.lastError, .unauthorised)
        XCTAssertEqual(service.lastError?.shortLabel, "Access denied")
    }

    func testCachedCatalogueSurvivesRelaunch() async {
        let first = makeService()
        await first.refreshAndWait()
        XCTAssertEqual(first.snapshot?.version.catalogueVersion, 20)

        // A new service instance stands in for a fresh launch. With every
        // request failing, anything it shows must have come from disk.
        fetcher.failEverything(with: .offline)
        let second = makeService()

        XCTAssertEqual(second.snapshot?.version.catalogueVersion, 20)
        XCTAssertFalse(second.snapshot?.isSeed ?? true)
        XCTAssertNotNil(second.lastSuccessfulUpdate)
    }

    func testClearingTheCacheFallsBackToTheBundledSeed() async {
        let service = makeService()
        await service.refreshAndWait()

        service.clearCache()

        // The seed ships with the app, so there is still a usable catalogue.
        XCTAssertTrue(service.snapshot?.isSeed ?? false)
        XCTAssertNil(service.lastSuccessfulUpdate)
    }

    // MARK: - Status reporting

    func testStatusSummaryReflectsState() async {
        let service = makeService()
        await service.refreshAndWait()
        XCTAssertEqual(service.statusSummary, "Catalogue up to date")

        fetcher.failEverything(with: .offline)
        await service.refreshAndWait()
        XCTAssertTrue(service.statusSummary.contains("Using offline data"))
    }
}

// MARK: - Test double

/// Serves catalogue files from memory and records what was asked for.
///
/// Access is serialised behind a lock: after a successful update the service
/// prefetches images through a concurrent task group, so several threads reach
/// this object at once.
final class FakeFetcher: CatalogueFetching, @unchecked Sendable {

    private let lock = NSLock()
    private var _responses: [String: Result<Data, CatalogueError>] = [:]
    private var _requestedFileNames: [String] = []

    var responses: [String: Result<Data, CatalogueError>] {
        get { lock.withLock { _responses } }
        set { lock.withLock { _responses = newValue } }
    }

    var requestedFileNames: [String] {
        lock.withLock { _requestedFileNames }
    }

    func fetch(_ url: URL) async throws -> Data {
        let name = url.lastPathComponent
        let response: Result<Data, CatalogueError>? = lock.withLock {
            _requestedFileNames.append(name)
            return _responses[name]
        }
        switch response {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case nil:
            throw CatalogueError.notFound(name)
        }
    }

    func resetLog() {
        lock.withLock { _requestedFileNames.removeAll() }
    }

    func failEverything(with error: CatalogueError) {
        lock.withLock {
            _responses = [:]
            for name in ["version.json", "catalogue.json", "bundles.json", "announcements.json"] {
                _responses[name] = .failure(error)
            }
        }
    }

    func serve(version: Int, catalogue: String) {
        lock.withLock {
            _responses["version.json"] = .success(Data(Self.versionJSON(version: version).utf8))
            _responses["catalogue.json"] = .success(Data(catalogue.utf8))
            _responses["bundles.json"] = .success(Data(Self.bundlesJSON.utf8))
            _responses["announcements.json"] = .success(Data(Self.announcementsJSON.utf8))
        }
    }

    // MARK: Fixtures

    static func versionJSON(version: Int) -> String {
        """
        {
          "schemaVersion": 1,
          "catalogueVersion": \(version),
          "environment": "staging",
          "publishedAt": "2026-07-20T09:00:00Z",
          "files": {
            "catalogue": "catalogue.json",
            "bundles": "bundles.json",
            "announcements": "announcements.json"
          }
        }
        """
    }

    static let validCatalogue = """
    {
      "schemaVersion": 1,
      "currency": "USD",
      "vehicles": [
        { "id": "model_y", "name": "Model Y", "order": 1 },
        { "id": "universal", "name": "All Vehicles", "order": 2 }
      ],
      "categories": [{ "id": "interior", "name": "Interior", "order": 1 }],
      "products": [
        {
          "id": "p_1", "sku": "TSL-MY-INT-0001", "name": "Liners", "price": 235,
          "categoryId": "interior", "compatibleVehicles": ["model_y"],
          "imageName": "p_1.png", "status": "active", "featured": true
        },
        {
          "id": "p_2", "sku": "TSL-UN-CHG-0002", "name": "Mobile Connector", "price": 230,
          "categoryId": "interior", "compatibleVehicles": ["universal"],
          "imageName": "p_2.png", "status": "active"
        }
      ]
    }
    """

    /// Same content, but the second product reuses the first product's SKU.
    static let duplicateSKUCatalogue = """
    {
      "schemaVersion": 1,
      "currency": "USD",
      "vehicles": [
        { "id": "model_y", "name": "Model Y", "order": 1 },
        { "id": "universal", "name": "All Vehicles", "order": 2 }
      ],
      "categories": [{ "id": "interior", "name": "Interior", "order": 1 }],
      "products": [
        {
          "id": "p_1", "sku": "TSL-MY-INT-0001", "name": "Liners", "price": 235,
          "categoryId": "interior", "compatibleVehicles": ["model_y"],
          "imageName": "p_1.png", "status": "active"
        },
        {
          "id": "p_2", "sku": "TSL-MY-INT-0001", "name": "Mobile Connector", "price": 230,
          "categoryId": "interior", "compatibleVehicles": ["universal"],
          "imageName": "p_2.png", "status": "active"
        }
      ]
    }
    """

    static let bundlesJSON = """
    {
      "schemaVersion": 1,
      "bundles": [
        {
          "id": "b_1", "name": "Delivery Kit", "productIds": ["p_1", "p_2"],
          "bundlePrice": 420, "imageName": "b_1.png",
          "compatibleVehicles": ["model_y"], "status": "active", "featured": true
        }
      ]
    }
    """

    static let announcementsJSON = """
    { "schemaVersion": 1, "announcements": [] }
    """
}
