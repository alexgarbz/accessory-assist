import SwiftUI

/// Bundle detail: what is in the bundle, what it costs, what it saves, and the
/// two operations staff perform on it — add everything to the cart, or step
/// through every SKU at the terminal.
///
/// The bundle price is a merchandising price, not a discount code: each SKU is
/// still scanned individually at the mPOS, which is why scan mode walks the
/// component products rather than showing one bundle barcode.
struct BundleDetailView: View {
    let bundle: AccessoryBundle

    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore

    @State private var isShowingScanMode = false

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }
    private var currency: String { snapshot?.currency ?? "USD" }
    private var products: [Product] { snapshot?.products(ids: bundle.productIds) ?? [] }
    private var listPrice: Decimal { snapshot?.listPrice(of: bundle) ?? .zero }
    private var saving: Decimal { snapshot?.saving(on: bundle) ?? .zero }

    /// Products listed in the bundle that are no longer in the catalogue.
    private var missingProductIds: [String] {
        guard let snapshot else { return [] }
        return bundle.productIds.filter { snapshot.product(id: $0) == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CatalogueImageView(imageRef: bundle.imageRef)
                    .aspectRatio(ImageRatio.product, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.m)

                header
                actions

                if !missingProductIds.isEmpty {
                    StatusBanner(
                        title: "Bundle out of date",
                        message: "\(missingProductIds.count) product\(missingProductIds.count == 1 ? "" : "s") in this bundle "
                            + "\(missingProductIds.count == 1 ? "is" : "are") no longer in the catalogue. Refresh, then check with the merchandising team.",
                        tone: .critical
                    )
                    .padding(.horizontal, Spacing.m)
                }

                if !bundle.detail.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        SectionHeader(title: "Notes")
                        Text(bundle.detail)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.m)
                }

                contents
            }
            .padding(.vertical, Spacing.m)
        }
        .background(Palette.canvas)
        // The bundle name is the headline in the content; the bar stays generic.
        .navigationTitle("Bundle")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingScanMode) {
            ScanModeView(items: products.map { ScanItem(product: $0) })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(bundle.name)
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !bundle.summary.isEmpty {
                Text(bundle.summary)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(Format.price(bundle.bundlePrice, currency: currency))
                    .font(TypeScale.heading)
                    .foregroundStyle(Palette.textPrimary)

                if saving > 0 {
                    Text(Format.price(listPrice, currency: currency))
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textTertiary)
                        .strikethrough()
                    StatusPill(text: "Saves \(Format.compactPrice(saving, currency: currency))", tone: .positive)
                }
            }
            .padding(.top, Spacing.xxs)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Spacing.m)
    }

    private var actions: some View {
        VStack(spacing: Spacing.xs) {
            Button {
                cart.addAll(products)
            } label: {
                Text("Add \(products.count) Items to Cart")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(products.isEmpty)

            Button {
                Haptics.impact(.medium)
                isShowingScanMode = true
            } label: {
                Label("Start mPOS Scan", systemImage: "barcode")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(products.isEmpty)
        }
        .padding(.horizontal, Spacing.m)
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Contents", subtitle: "\(products.count) accessories")
                .padding(.horizontal, Spacing.m)

            LazyVStack(spacing: 0) {
                ForEach(products) { product in
                    ProductRow(
                        product: product,
                        snapshot: snapshot,
                        isFavourite: favourites.contains(product.id),
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
        }
    }
}
