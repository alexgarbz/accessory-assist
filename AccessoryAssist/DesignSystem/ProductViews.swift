import SwiftUI

/// Dense catalogue row.
///
/// Shows exactly what is needed to pick a product from a list — image, name,
/// price, compatibility, category, favourite state and add to cart — and no
/// description. Long-form copy belongs on the detail screen.
struct ProductRow: View {
    let product: Product
    let snapshot: CatalogueSnapshot?
    let isFavourite: Bool
    let quantityInCart: Int
    let onToggleFavourite: () -> Void
    let onAdd: () -> Void

    private var compatibility: String {
        snapshot?.compatibilityLabel(for: product) ?? "All vehicles"
    }

    private var category: String {
        snapshot?.categoryName(id: product.categoryId) ?? product.categoryId
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            NavigationLink(value: product) {
                HStack(spacing: Spacing.m) {
                    CatalogueImageView(imageRef: product.imageRef, cornerRadius: Radius.control)
                        .frame(width: 68, height: 68)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(product.name)
                            .font(TypeScale.productName)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text("\(category) · \(compatibility)")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)

                        HStack(spacing: Spacing.xs) {
                            Text(Format.compactPrice(product.price, currency: snapshot?.currency ?? "USD"))
                                .font(TypeScale.price)
                                .foregroundStyle(Palette.textPrimary)

                            if product.status == .discontinued {
                                StatusPill(text: "Discontinued", tone: .warning)
                            }
                            if quantityInCart > 0 {
                                StatusPill(text: "In cart · \(quantityInCart)", tone: .accent)
                            }
                        }
                        .padding(.top, 1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableRowStyle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens product detail")

            HStack(spacing: 0) {
                FavouriteButton(isFavourite: isFavourite, action: onToggleFavourite)
                AddToCartIconButton(action: onAdd)
                    .opacity(product.status.isSellable ? 1 : 0.35)
                    .disabled(!product.status.isSellable)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var accessibilityLabel: String {
        var parts = [product.name, Format.price(product.price, currency: snapshot?.currency ?? "USD"), category, "Fits \(compatibility)"]
        if product.status == .discontinued { parts.append("Discontinued") }
        if isFavourite { parts.append("Favourite") }
        if quantityInCart > 0 { parts.append("\(quantityInCart) in cart") }
        return parts.joined(separator: ", ")
    }
}

/// Compact add-to-cart control used in rows and cards.
struct AddToCartIconButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: IconSize.medium, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to cart")
    }
}

/// Card used in the Home carousels. Image-led, minimal chrome.
struct ProductCard: View {
    let product: Product
    let snapshot: CatalogueSnapshot?
    let isFavourite: Bool
    let onToggleFavourite: () -> Void

    var width: CGFloat = 168

    var body: some View {
        NavigationLink(value: product) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    CatalogueImageView(imageRef: product.imageRef)
                        .aspectRatio(ImageRatio.product, contentMode: .fit)
                        .frame(width: width)

                    FavouriteButton(isFavourite: isFavourite, size: 36, action: onToggleFavourite)
                        .padding(Spacing.xxs)
                }

                Text(product.name)
                    .font(TypeScale.productName)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .top)

                Text(Format.compactPrice(product.price, currency: snapshot?.currency ?? "USD"))
                    .font(TypeScale.price)
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(Format.price(product.price, currency: snapshot?.currency ?? "USD"))")
    }
}

/// Bundle card. Larger than a product card — bundles are a deliberate
/// merchandising choice and get the wider surface.
struct BundleCard: View {
    let bundle: AccessoryBundle
    let snapshot: CatalogueSnapshot?
    var width: CGFloat = 264

    private var saving: Decimal {
        snapshot?.saving(on: bundle) ?? .zero
    }

    var body: some View {
        NavigationLink(value: bundle) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                CatalogueImageView(imageRef: bundle.imageRef)
                    .aspectRatio(ImageRatio.hero, contentMode: .fit)
                    .frame(width: width)

                Text(bundle.name)
                    .font(TypeScale.productName)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(Format.compactPrice(bundle.bundlePrice, currency: snapshot?.currency ?? "USD"))
                        .font(TypeScale.price)
                        .foregroundStyle(Palette.textPrimary)
                    if saving > 0 {
                        Text("Saves \(Format.compactPrice(saving, currency: snapshot?.currency ?? "USD"))")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                Text("\(bundle.productIds.count) items")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
