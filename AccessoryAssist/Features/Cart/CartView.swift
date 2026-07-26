import SwiftUI

/// The working cart.
///
/// Not a checkout: no payment, no customer record, no order submission. It is a
/// list of SKUs being sold in this interaction, with a running total to read out
/// and a single primary action — start scanning at the mPOS.
///
/// Scan mode expands quantities, so a line with three units is presented three
/// times rather than once. Staff scanning down a queue never have to remember
/// how many times to scan a given barcode.
struct CartView: View {
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore

    @State private var isShowingScanMode = false
    @State private var isConfirmingClear = false

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }
    private var currency: String { snapshot?.currency ?? "USD" }
    private var lines: [CartStore.Line] { cart.lines(in: snapshot) }
    private var unavailable: [String] { cart.unavailableIds(in: snapshot) }

    /// One entry per unit, so the barcode sequence matches what is scanned.
    private var scanItems: [ScanItem] {
        lines.flatMap { line in
            (0..<line.quantity).map { unit in
                ScanItem(
                    product: line.product,
                    subtitle: line.quantity > 1 ? "Unit \(unit + 1) of \(line.quantity)" : nil,
                    idSuffix: "#\(unit)"
                )
            }
        }
    }

    var body: some View {
        Group {
            if lines.isEmpty && unavailable.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "Cart is empty",
                        message: "Add accessories from the catalogue, then start scanning at the terminal.",
                        systemImage: "cart"
                    )
                }
            } else {
                VStack(spacing: 0) {
                    List {
                        Section {
                            ForEach(lines) { line in
                                CartLineRow(
                                    line: line,
                                    currency: currency,
                                    onDecrement: { cart.decrement(line.product.id) },
                                    onIncrement: { cart.increment(line.product.id) }
                                )
                                .listRowInsets(EdgeInsets(
                                    top: Spacing.xs,
                                    leading: Spacing.m,
                                    bottom: Spacing.xs,
                                    trailing: Spacing.m
                                ))
                                .listRowBackground(Palette.canvas)
                                .listRowSeparatorTint(Palette.divider)
                            }
                            .onDelete { offsets in
                                for index in offsets where lines.indices.contains(index) {
                                    cart.remove(lines[index].product.id)
                                }
                            }
                        }

                        if !unavailable.isEmpty {
                            Section {
                                StatusBanner(
                                    title: "\(unavailable.count) item\(unavailable.count == 1 ? "" : "s") no longer in the catalogue",
                                    message: "Removed from the total. They may have been discontinued in the latest publish.",
                                    tone: .warning,
                                    actionTitle: "Remove",
                                    action: { unavailable.forEach(cart.remove) }
                                )
                                .listRowBackground(Palette.canvas)
                            }
                        }
                    }
                    .listStyle(.plain)

                    summaryBar
                }
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Cart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cart.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { isConfirmingClear = true }
                        .buttonStyle(DestructiveTextButtonStyle())
                }
            }
        }
        .confirmationDialog("Clear the cart?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Cart", role: .destructive) { cart.clear() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This removes all \(cart.itemCount) items from the current sale.")
        }
        .fullScreenCover(isPresented: $isShowingScanMode) {
            ScanModeView(items: scanItems)
        }
        .catalogueDestinations()
    }

    private var summaryBar: some View {
        VStack(spacing: Spacing.s) {
            Hairline()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Total")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textTertiary)
                    Text(Format.price(cart.total(in: snapshot), currency: currency))
                        .font(TypeScale.heading)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(cart.itemCount) item\(cart.itemCount == 1 ? "" : "s")")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.m)
            .accessibilityElement(children: .combine)

            Button {
                Haptics.impact(.medium)
                isShowingScanMode = true
            } label: {
                Label("Start mPOS Scan", systemImage: "barcode")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.m)
            .disabled(scanItems.isEmpty)
        }
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xs)
        .background(Palette.canvas)
    }
}

/// A single cart line: image, name, SKU, unit price, quantity stepper, total.
struct CartLineRow: View {
    let line: CartStore.Line
    let currency: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            CatalogueImageView(imageRef: line.product.imageRef, cornerRadius: Radius.control)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(line.product.name)
                    .font(TypeScale.productName)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)

                Text(line.product.sku)
                    .font(TypeScale.mono)
                    .foregroundStyle(Palette.textTertiary)

                Text("\(Format.compactPrice(line.product.price, currency: currency)) each")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(Format.price(line.lineTotal, currency: currency))
                    .font(TypeScale.price)
                    .foregroundStyle(Palette.textPrimary)
                QuantityStepper(
                    quantity: line.quantity,
                    onDecrement: onDecrement,
                    onIncrement: onIncrement
                )
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(line.product.name), \(line.quantity) at \(Format.price(line.product.price, currency: currency))")
    }
}
