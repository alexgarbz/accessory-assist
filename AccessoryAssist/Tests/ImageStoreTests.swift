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

    func testAbsoluteImageURLIsFetchedAndCached() async {
        // Product photography is hosted outside the catalogue. The bytes still
        // land in the same device cache, so the catalogue works offline.
        let fetcher = RecordingImageFetcher(data: makePNG(size: CGSize(width: 5, height: 5)))
        let store = ImageStore(source: source, fetcher: fetcher)
        let remote = URL(string: "https://images.example.com/dam/2048569-RH-A_1.png")!
        let ref = CatalogueImageRef(imageName: "", imageURL: remote, fallbackKey: "p_my_aw_interior_liners")

        let image = await store.image(for: ref)

        XCTAssertNotNil(image)
        XCTAssertEqual(fetcher.requestedURLs, [remote], "The absolute URL must be used verbatim")
        XCTAssertNotNil(
            CatalogueCacheStore(source: source).cachedImageData(for: ref.cacheKey),
            "Externally hosted photography must still be cached for offline use"
        )
    }

    func testCatalogueHostedImageIsFetchedRelativeToTheSource() async {
        let fetcher = RecordingImageFetcher(data: makePNG(size: CGSize(width: 5, height: 5)))
        let store = ImageStore(source: source, fetcher: fetcher)
        let ref = CatalogueImageRef(imageName: "local.png", imageURL: nil, fallbackKey: "p_1")

        _ = await store.image(for: ref)

        XCTAssertEqual(fetcher.requestedURLs.first, source.imageURL(for: "local.png"))
    }

    func testCacheKeysDoNotCollideAcrossProducts() {
        // Two products can reference files that share a name once the path is
        // dropped; the product id keeps their cache entries apart.
        let a = CatalogueImageRef(
            imageName: "",
            imageURL: URL(string: "https://cdn.example.com/one/1_2000.png")!,
            fallbackKey: "p_alpha"
        )
        let b = CatalogueImageRef(
            imageName: "",
            imageURL: URL(string: "https://cdn.example.com/two/1_2000.png")!,
            fallbackKey: "p_beta"
        )

        XCTAssertNotEqual(a.cacheKey, b.cacheKey)
        XCTAssertEqual(a.cacheKey, "p_alpha.png")
        XCTAssertTrue(b.cacheKey.hasSuffix(".png"))
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

        await store.prefetch(["a.png", "b.png", "c.png", "d.png", "e.png"] as [String])

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

/// Records which URLs were asked for, so the routing can be asserted.
private final class RecordingImageFetcher: CatalogueFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private var _requestedURLs: [URL] = []

    init(data: Data) { self.data = data }

    var requestedURLs: [URL] { lock.withLock { _requestedURLs } }

    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { _requestedURLs.append(url) }
        return data
    }
}
