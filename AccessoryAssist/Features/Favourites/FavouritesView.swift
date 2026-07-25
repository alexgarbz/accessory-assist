import SwiftUI

/// Favourites: the short list of accessories a store sells constantly.
///
/// Ordered most-recently-favourited first and offering a scan run across the
/// whole list, so the handful of SKUs sold every day are two taps from a
/// barcode.
struct FavouritesView: View {
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore

    @State private var isShowingScanMode = false

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }
    private var products: [Product] { favourites.products(in: snapshot) }

    var body: some View {
        Group {
            if products.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "No favourites yet",
                        message: "Tap the heart on any accessory to keep it here. Favourites appear on Home for fast access.",
                        systemImage: "heart"
                    )
                }
            } else {
                VStack(spacing: 0) {
                    // Tapping the filled heart removes a favourite, so this
                    // list needs no swipe action and no disclosure chevrons.
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(products) { product in
                                ProductRow(
                                    product: product,
                                    snapshot: snapshot,
                                    isFavourite: true,
                                    quantityInCart: cart.quantity(of: product.id),
                                    onToggleFavourite: { favourites.toggle(product.id) },
                                    onAdd: { cart.add(product) }
                                )
                                .padding(.horizontal, Spacing.m)

                                if product.id != products.last?.id {
                                    Hairline(inset: Spacing.m + 68 + Spacing.m)
                                }
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }

                    VStack(spacing: 0) {
                        Hairline()
                        Button {
                            Haptics.impact(.medium)
                            isShowingScanMode = true
                        } label: {
                            Label("Start mPOS Scan", systemImage: "barcode")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(Spacing.m)
                    }
                    .background(Palette.canvas)
                }
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Favourites")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingScanMode) {
            ScanModeView(items: products.map { ScanItem(product: $0) })
        }
        .catalogueDestinations()
    }
}
