import Foundation

/// Errors surfaced to the catalogue status UI. Each case maps to language staff
/// can act on rather than a raw networking error.
enum CatalogueError: LocalizedError, Equatable {
    case offline
    case timedOut
    case unauthorised
    case notFound(String)
    case server(Int)
    case malformed(String)
    case rejected([CatalogueValidator.Issue])
    case cacheWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No network connection."
        case .timedOut:
            return "The catalogue server did not respond."
        case .unauthorised:
            return "The catalogue source rejected this request. Check the source configuration."
        case .notFound(let file):
            return "\(file) was not found at the catalogue source."
        case .server(let code):
            return "The catalogue server returned status \(code)."
        case .malformed(let file):
            return "\(file) could not be read. The previous catalogue is still in use."
        case .rejected(let issues):
            let count = issues.count
            return "The published catalogue failed validation (\(count) \(count == 1 ? "problem" : "problems")). The previous catalogue is still in use."
        case .cacheWriteFailed:
            return "The catalogue could not be saved to this device."
        }
    }

    /// Short label for the status row.
    var shortLabel: String {
        switch self {
        case .offline: return "Offline"
        case .timedOut: return "Timed out"
        case .unauthorised: return "Access denied"
        case .notFound: return "Not found"
        case .server: return "Server error"
        case .malformed: return "Invalid content"
        case .rejected: return "Rejected"
        case .cacheWriteFailed: return "Storage error"
        }
    }
}

/// Fetches raw catalogue files. Kept behind a protocol so tests can drive the
/// update flow without touching the network.
protocol CatalogueFetching {
    func fetch(_ url: URL) async throws -> Data
}

struct CatalogueRemoteClient: CatalogueFetching {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        // The app manages its own validated cache; HTTP caching would only
        // confuse the version comparison.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return data }
            switch http.statusCode {
            case 200...299:
                return data
            case 401, 403:
                throw CatalogueError.unauthorised
            case 404:
                throw CatalogueError.notFound(url.lastPathComponent)
            default:
                throw CatalogueError.server(http.statusCode)
            }
        } catch let error as CatalogueError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost:
                throw CatalogueError.offline
            case .timedOut:
                throw CatalogueError.timedOut
            default:
                throw CatalogueError.offline
            }
        }
    }
}
