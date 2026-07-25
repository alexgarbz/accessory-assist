import Foundation
import SwiftUI

/// Products a member of staff has marked for fast access.
///
/// Insertion order is kept: the most recently favourited product appears first,
/// which matches how the Home strip is used in practice — the accessory being
/// pushed this week ends up at the front without anyone reordering anything.
@MainActor
final class FavouritesStore: ObservableObject {

    @Published private(set) var productIds: [String] = [] {
        didSet { defaults.set(productIds, forKey: storageKey) }
    }

    private let defaults: UserDefaults
    private let storageKey = "favourites.productIds.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        productIds = defaults.stringArray(forKey: storageKey) ?? []
    }

    var isEmpty: Bool { productIds.isEmpty }
    var count: Int { productIds.count }

    func contains(_ productId: String) -> Bool { productIds.contains(productId) }

    func toggle(_ productId: String) {
        if let index = productIds.firstIndex(of: productId) {
            productIds.remove(at: index)
            Haptics.selection()
        } else {
            productIds.insert(productId, at: 0)
            Haptics.success()
        }
    }

    func remove(_ productId: String) {
        productIds.removeAll { $0 == productId }
    }

    /// Favourites resolved against the catalogue, dropping anything that has
    /// since been removed from the published content.
    func products(in snapshot: CatalogueSnapshot?) -> [Product] {
        guard let snapshot else { return [] }
        return productIds.compactMap { snapshot.product(id: $0) }
    }
}
