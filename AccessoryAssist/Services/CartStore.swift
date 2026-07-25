import Foundation
import SwiftUI

/// The working list of accessories being sold in the current interaction.
///
/// This is not a checkout. Nothing is charged here — the cart exists so staff
/// can assemble a set of SKUs, read the running total to the customer, and step
/// through the barcodes at the mPOS terminal.
@MainActor
final class CartStore: ObservableObject {

    struct Line: Identifiable, Equatable {
        let product: Product
        var quantity: Int
        var id: String { product.id }
        var lineTotal: Decimal { product.price * Decimal(quantity) }
    }

    /// productId → quantity. Persisted so a backgrounded app never loses a cart
    /// mid-sale.
    @Published private(set) var quantities: [String: Int] = [:] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let storageKey = "cart.quantities.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: storageKey) as? [String: Int] {
            quantities = stored.filter { $0.value > 0 }
        }
    }

    // MARK: - Queries

    var isEmpty: Bool { quantities.isEmpty }

    var itemCount: Int { quantities.values.reduce(0, +) }

    var distinctItemCount: Int { quantities.count }

    func quantity(of productId: String) -> Int { quantities[productId] ?? 0 }

    func contains(_ productId: String) -> Bool { quantity(of: productId) > 0 }

    /// Resolve the cart against a catalogue snapshot.
    ///
    /// Products that have disappeared from the catalogue are dropped from the
    /// result rather than rendered as blanks; `unavailableIds` reports them so
    /// the cart screen can tell staff what happened.
    func lines(in snapshot: CatalogueSnapshot?) -> [Line] {
        guard let snapshot else { return [] }
        return quantities
            .compactMap { productId, quantity -> Line? in
                guard quantity > 0, let product = snapshot.product(id: productId) else { return nil }
                return Line(product: product, quantity: quantity)
            }
            .sorted { $0.product.name < $1.product.name }
    }

    func unavailableIds(in snapshot: CatalogueSnapshot?) -> [String] {
        guard let snapshot else { return Array(quantities.keys).sorted() }
        return quantities.keys.filter { snapshot.product(id: $0) == nil }.sorted()
    }

    func total(in snapshot: CatalogueSnapshot?) -> Decimal {
        lines(in: snapshot).reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    // MARK: - Mutations

    func add(_ product: Product, quantity: Int = 1) {
        guard quantity > 0 else { return }
        quantities[product.id, default: 0] += quantity
        Haptics.success()
    }

    func addAll(_ products: [Product]) {
        guard !products.isEmpty else { return }
        for product in products {
            quantities[product.id, default: 0] += 1
        }
        Haptics.success()
    }

    func setQuantity(_ quantity: Int, for productId: String) {
        if quantity <= 0 {
            quantities.removeValue(forKey: productId)
        } else {
            quantities[productId] = quantity
        }
    }

    func increment(_ productId: String) {
        quantities[productId, default: 0] += 1
        Haptics.selection()
    }

    func decrement(_ productId: String) {
        let next = quantity(of: productId) - 1
        setQuantity(next, for: productId)
        Haptics.selection()
    }

    func remove(_ productId: String) {
        quantities.removeValue(forKey: productId)
        Haptics.impact()
    }

    func clear() {
        quantities.removeAll()
        Haptics.impact()
    }

    private func persist() {
        defaults.set(quantities, forKey: storageKey)
    }
}
