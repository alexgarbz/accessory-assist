import XCTest
import UIKit
@testable import AccessoryAssist

/// Image caching tests.
///
/// Product imagery has to survive losing connectivity mid-shift, and it has to
/// update when the merchandising team replaces a file. Those two requirements
/// pull in opposite directions, and the order of the lookup layers is what
/// resolves them — so that order is pinned down here.
@MainActor
final class ImageStoreTests: XCTestCase {

    private var source: CatalogueSource!

    override func setUp() async throws {
        try await super.setUp()
        source = .custom(URL(string: "https://images.test/\(UUID().uuidString)/")!)
    }

    override func tearDown() async throws {
        CatalogueCacheStore(source: source).clear()
        try await super.tearDown()
    }

    /// A solid-colour PNG of a known pixel size, used to tell one image from
    /// another. The renderer scale is pinned to 1 so the pixel dimensions and
    /// the decoded `UIImage.size` agree.
    private func makePNG(size: CGSize) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()!
    }

    func testFetchedImageIsWrittenToTheDeviceCache() async {
        let fetcher = StubImageFetcher(data: makePNG(size: CGSize(width: 4, height: 4)))
        let store = ImageStore(source: source, fetcher: fetcher)

        let image = await store.image(named: "brand_new.png")

        XCTAssertNotNil(image)
        XCTAssertNotNil(
            CatalogueCacheStore(source: source).cachedImageData(for: "brand_new.png"),
            "A fetched image must be persisted so the catalogue works offline"
        )
    }

    func testCachedImageIsServedWhenTheNetworkIsGone() async {
        let fetcher = StubImageFetcher(data: makePNG(size: CGSize(width: 4, height: 4)))
        let warmStore = ImageStore(source: source, fetcher: fetcher)
        _ = await warmStore.image(named: "cached.png")

        // A new store stands in for a relaunch, with every request failing.
        let coldStore = ImageStore(source: source, fetcher: FailingImageFetcher())
        let image = await coldStore.image(named: "cached.png")

        XCTAssertNotNil(image, "The device cache must survive a relaunch")
    }

    /// An image name that genuinely ships inside the app, taken from the seed
    /// catalogue rather than hard-coded — a content change must not be able to
    /// break these tests.
    private func bundledImageName() throws -> String {
        let seed = try XCTUnwrap(SeedCatalogue.load(), "The app must ship a seed catalogue")
        return try XCTUnwrap(seed.catalogue.products.first?.imageName)
    }

    func testFallsBackToTheImageBundledWithTheAppWhenOffline() async throws {
        let store = ImageStore(source: source, fetcher: FailingImageFetcher())

        let image = await store.image(named: try bundledImageName())

        XCTAssertNotNil(image, "A device that has never had a connection still shows imagery")
    }

    func testPublishedImageWinsOverTheCopyBundledWithTheApp() async throws {
        // Replacing artwork by overwriting the file in images/ is a documented
        // content operation. If the bundled copy were preferred, that change
        // would never reach a device that shipped with the old image.
        let name = try bundledImageName()
        let published = makePNG(size: CGSize(width: 7, height: 7))
        let store = ImageStore(source: source, fetcher: StubImageFetcher(data: published))

        let image = await store.image(named: name)

        XCTAssertEqual(image?.size.width, 7, "The published image must win over the bundled one")
        XCTAssertNotNil(CatalogueCacheStore(source: source).cachedImageData(for: name))
    }

    func testUnresolvableImageReturnsNilRatherThanThrowing() async {
        let store = ImageStore(source: source, fetcher: FailingImageFetcher())
        let image = await store.image(named: "no_such_image_anywhere.png")
        XCTAssertNil(image)
    }

    func testEmptyImageNameIsIgnored() async {
        let store = ImageStore(source: source, fetcher: StubImageFetcher(data: makePNG(size: CGSize(width: 4, height: 4))))
        let image = await store.image(named: "")
        XCTAssertNil(image)
    }

    func testPrefetchWarmsTheCacheForEveryName() async {
        let fetcher = StubImageFetcher(data: makePNG(size: CGSize(width: 4, height: 4)))
        let store = ImageStore(source: source, fetcher: fetcher)

        await store.prefetch(["a.png", "b.png", "c.png", "d.png", "e.png"])

        let cache = CatalogueCacheStore(source: source)
        for name in ["a.png", "b.png", "c.png", "d.png", "e.png"] {
            XCTAssertNotNil(cache.cachedImageData(for: name), "\(name) was not prefetched")
        }
    }
}

// MARK: - Test doubles

private final class StubImageFetcher: CatalogueFetching, @unchecked Sendable {
    private let data: Data
    init(data: Data) { self.data = data }
    func fetch(_ url: URL) async throws -> Data { data }
}

private final class FailingImageFetcher: CatalogueFetching, @unchecked Sendable {
    func fetch(_ url: URL) async throws -> Data { throw CatalogueError.offline }
}
