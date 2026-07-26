import Foundation

/// Where a product or bundle image comes from.
///
/// Content can point at an image two ways:
///
///  * `imageURL` — an absolute URL, used for product photography that is
///    already hosted elsewhere. Nothing is copied into this repository; the app
///    fetches it and caches it on the device for offline use.
///  * `imageName` — a bare file name served from `<catalogue base URL>/images/`,
///    for imagery published alongside the catalogue itself.
///
/// An absolute URL wins when both are present.
struct CatalogueImageRef: Hashable {
    /// Stable name used for the on-disk cache entry.
    let cacheKey: String
    /// Absolute location, when the image is hosted outside the catalogue.
    let absoluteURL: URL?

    var isEmpty: Bool { cacheKey.isEmpty && absoluteURL == nil }

    static let none = CatalogueImageRef(cacheKey: "", absoluteURL: nil)

    /// Build a reference from the two content fields.
    ///
    /// - Parameters:
    ///   - imageName: bare file name published with the catalogue.
    ///   - imageURL: absolute URL to externally hosted photography.
    ///   - fallbackKey: used as the cache name when an absolute URL carries no
    ///     usable file name of its own — the product id, in practice.
    init(imageName: String, imageURL: URL?, fallbackKey: String) {
        if let imageURL {
            absoluteURL = imageURL
            cacheKey = CatalogueImageRef.cacheKey(for: imageURL, fallbackKey: fallbackKey)
        } else {
            absoluteURL = nil
            cacheKey = imageName
        }
    }

    init(cacheKey: String, absoluteURL: URL?) {
        self.cacheKey = cacheKey
        self.absoluteURL = absoluteURL
    }

    /// A file-system-safe cache name for a remote image.
    ///
    /// Two different products can reference file names that collide once the
    /// directory structure is dropped, so the product id is folded in.
    static func cacheKey(for url: URL, fallbackKey: String) -> String {
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        let safe = fallbackKey.map { character -> Character in
            character.isLetter || character.isNumber || character == "_" ? character : "_"
        }
        return String(safe).lowercased() + "." + ext
    }
}
