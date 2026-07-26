import SwiftUI

/// Product detail: the long-form information the catalogue rows deliberately
/// omit, plus the two actions that matter — Show Barcode and Add to Cart.
///
/// Show Barcode is the primary action rather than Add to Cart. Staff reach this
/// screen most often with the customer already committed, needing the SKU on
/// screen at the terminal.
struct ProductDetailView: View {
    let product: Product

    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore

    @State private var isShowingScanMode = false

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }
    private var currency: String { snapshot?.currency ?? "USD" }

    /// Bundles that contain this product — an upsell prompt staff can act on
    /// without leaving the screen.
    private var relatedBundles: [AccessoryBundle] {
        (snapshot?.activeBundles ?? []).filter { $0.productIds.contains(product.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CatalogueImageView(imageRef: product.imageRef)
                    .aspectRatio(ImageRatio.product, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.m)

                header
                actions
                specifications

                if !product.detail.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        SectionHeader(title: "Description")
                        Text(product.detail)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.m)
                }

                if let fitNotes = product.fitNotes, !fitNotes.isEmpty {
                    StatusBanner(
                        title: "Fitment",
                        message: fitNotes,
                        tone: .warning,
                        systemImage: "checkmark.seal"
                    )
                    .padding(.horizontal, Spacing.m)
                }

                if !relatedBundles.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "In Bundles")
                            .padding(.horizontal, Spacing.m)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                ForEach(relatedBundles) { bundle in
                                    BundleCard(bundle: bundle, snapshot: snapshot)
                                }
                            }
                            .padding(.horizontal, Spacing.m)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            .padding(.vertical, Spacing.m)
        }
        .background(Palette.canvas)
        // The product name is already the largest thing on the screen; the bar
        // carries the SKU instead, which stays useful while scrolling.
        .navigationTitle(product.sku)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FavouriteButton(isFavourite: favourites.contains(product.id)) {
                    favourites.toggle(product.id)
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingScanMode) {
            ScanModeView(items: [ScanItem(product: product)])
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                if product.status == .discontinued {
                    StatusPill(text: "Discontinued", tone: .warning)
                }
                if product.status == .upcoming {
                    StatusPill(text: "Upcoming", tone: .accent)
                }
                if cart.quantity(of: product.id) > 0 {
                    StatusPill(text: "In cart · \(cart.quantity(of: product.id))", tone: .accent)
                }
            }

            Text(product.name)
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !product.summary.isEmpty {
                Text(product.summary)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(Format.price(product.price, currency: currency))
                .font(TypeScale.heading)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, Spacing.xxs)
                .accessibilityLabel("Price \(Format.price(product.price, currency: currency))")
        }
        .padding(.horizontal, Spacing.m)
    }

    private var actions: some View {
        VStack(spacing: Spacing.xs) {
            Button {
                Haptics.impact(.medium)
                isShowingScanMode = true
            } label: {
                Label("Show Barcode", systemImage: "barcode")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                cart.add(product)
            } label: {
                Text(cart.contains(product.id) ? "Add Another to Cart" : "Add to Cart")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!product.status.isSellable)
            .opacity(product.status.isSellable ? 1 : 0.4)
        }
        .padding(.horizontal, Spacing.m)
    }

    private var specifications: some View {
        VStack(spacing: 0) {
            DetailRow(label: "SKU", value: product.sku, isMonospaced: true)
                .accessibilityLabel("SKU \(Format.spokenSKU(product.sku))")
            Hairline()
            DetailRow(label: "Category", value: snapshot?.categoryName(id: product.categoryId) ?? product.categoryId)
            Hairline()
            DetailRow(label: "Fits", value: snapshot?.compatibilityLabel(for: product) ?? "All vehicles")
            Hairline()
            DetailRow(
                label: "Status",
                value: product.status.label,
                valueColor: product.status.isSellable ? Palette.textPrimary : Palette.warning
            )
        }
        .padding(.horizontal, Spacing.m)
    }
}
