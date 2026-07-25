import SwiftUI

/// Value-typed navigation destinations.
///
/// Products and bundles push by value, so any screen can link to any other
/// without threading bindings through the view tree.
enum CatalogueRoute: Hashable {
    case all
    case category(String)
    case cart
    case favourites
    case status
    case vehicleSelection
}

extension View {
    /// Register the destinations every stack in the app shares.
    func catalogueDestinations() -> some View {
        self
            .navigationDestination(for: Product.self) { product in
                ProductDetailView(product: product)
            }
            .navigationDestination(for: AccessoryBundle.self) { bundle in
                BundleDetailView(bundle: bundle)
            }
            .navigationDestination(for: CatalogueRoute.self) { route in
                switch route {
                case .all:
                    CatalogueView()
                case .category(let categoryId):
                    CatalogueView(initialCategoryId: categoryId)
                case .cart:
                    CartView()
                case .favourites:
                    FavouritesView()
                case .status:
                    CatalogueStatusView()
                case .vehicleSelection:
                    VehicleSelectionView()
                }
            }
    }
}
