import Foundation

/// Where the app fetches catalogue content from.
///
/// Production tracks the `main` branch (approved content). Staging tracks the
/// `staging` branch (upcoming products, pricing and bundle tests). Custom
/// points at any base URL — used against a local server during development, and
/// the hook an internal deployment would use to point at an authenticated CDN.
enum CatalogueSource: Hashable {
    case production
    case staging
    case custom(URL)

    var displayName: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .custom: return "Custom"
        }
    }

    /// Short label shown in the settings row and the developer badge.
    var shortLabel: String {
        switch self {
        case .production: return "main"
        case .staging: return "staging"
        case .custom: return "custom"
        }
    }

    var baseURL: URL {
        switch self {
        case .production: return RemoteCatalogueConfiguration.productionBaseURL
        case .staging: return RemoteCatalogueConfiguration.stagingBaseURL
        case .custom(let url): return url
        }
    }

    func url(for fileName: String) -> URL {
        baseURL.appendingPathComponent(fileName)
    }

    func imageURL(for imageName: String) -> URL {
        baseURL.appendingPathComponent("images").appendingPathComponent(imageName)
    }

    // MARK: - Persistence

    /// Stable string form written to `UserDefaults`.
    var storageValue: String {
        switch self {
        case .production: return "production"
        case .staging: return "staging"
        case .custom(let url): return "custom:\(url.absoluteString)"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "production":
            self = .production
        case "staging":
            self = .staging
        default:
            guard storageValue.hasPrefix("custom:") else { return nil }
            let raw = String(storageValue.dropFirst("custom:".count))
            guard let url = URL(string: raw), url.scheme != nil else { return nil }
            self = .custom(url)
        }
    }

    /// Cache directory name, so switching source never mixes two catalogues.
    var cacheKey: String {
        switch self {
        case .production: return "production"
        case .staging: return "staging"
        case .custom(let url):
            let sanitised = url.absoluteString.map { character -> Character in
                character.isLetter || character.isNumber ? character : "_"
            }
            return "custom_" + String(sanitised).suffix(48)
        }
    }
}

/// Compile-time defaults for the hosted catalogue.
///
/// The repository is private, so these raw URLs are not anonymously readable.
/// See documentation/architecture.md — a real internal deployment must serve
/// this content from an authenticated endpoint. No access token is embedded in
/// the app, by design.
enum RemoteCatalogueConfiguration {
    static let repositoryOwner = "alexgarbz"
    static let repositoryName = "accessory-assist"
    static let productionBranch = "main"
    static let stagingBranch = "staging"
    static let contentDirectory = "remote-data"

    static var productionBaseURL: URL { rawBaseURL(branch: productionBranch) }
    static var stagingBaseURL: URL { rawBaseURL(branch: stagingBranch) }

    static func rawBaseURL(branch: String) -> URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://raw.githubusercontent.com/\(repositoryOwner)/\(repositoryName)/\(branch)/\(contentDirectory)/")!
    }
}
