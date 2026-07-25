import SwiftUI

/// The full accessory catalogue with category and vehicle filters.
///
/// A single dense list rather than a grid: staff scan down names and SKUs, and
/// a grid of thumbnails is slower to read than a column of labelled rows.
struct CatalogueView: View {
    var initialCategoryId: String?

    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore
    @EnvironmentObject private var settings: AppSettings

    @State private var categoryId: String?
    @State private var searchText = ""
    @State private var showsDiscontinued = false
    @State private var showsVehicleSheet = false

    init(initialCategoryId: String? = nil) {
        self.initialCategoryId = initialCategoryId
        _categoryId = State(initialValue: initialCategoryId)
    }

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }

    private var products: [Product] {
        guard let snapshot else { return [] }
        return snapshot.catalogue.products
            .filter { product in
                if !showsDiscontinued && !product.status.isSellable { return false }
                if let categoryId, product.categoryId != categoryId { return false }
                if !product.fits(vehicleId: settings.selectedVehicleId) { return false }
                return product.matches(query: searchText)
            }
            .sorted { $0.name < $1.name }
    }

    private var vehicleName: String? {
        guard let id = settings.selectedVehicleId else { return nil }
        return snapshot?.vehicle(id: id)?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            filters

            if catalogue.snapshot == nil {
                ScrollView {
                    ErrorStateView(
                        title: "Catalogue Unavailable",
                        message: catalogue.lastError?.localizedDescription
                            ?? "No catalogue has been downloaded to this device yet.",
                        retryTitle: "Refresh Catalogue",
                        retry: { catalogue.refresh(force: true) }
                    )
                }
            } else if products.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "No accessories match",
                        message: emptyMessage,
                        systemImage: "line.3.horizontal.decrease.circle",
                        actionTitle: hasActiveFilter ? "Clear Filters" : nil,
                        action: hasActiveFilter ? clearFilters : nil
                    )
                }
            } else {
                // A plain stack rather than a List: List adds a disclosure
                // chevron to every navigating row, and this design separates
                // rows with a hairline and space, not with chrome.
                ScrollView {
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
                    .padding(.vertical, Spacing.xs)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search name or SKU")
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show Discontinued", isOn: $showsDiscontinued)
                    Button {
                        showsVehicleSheet = true
                    } label: {
                        Label("Change Vehicle", systemImage: "car")
                    }
                    if settings.selectedVehicleId != nil {
                        Button("Clear Vehicle Filter") { settings.selectedVehicleId = nil }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Catalogue options")
                }
            }
        }
        .refreshable { await catalogue.refreshAndWait() }
        .sheet(isPresented: $showsVehicleSheet) {
            NavigationStack {
                VehicleSelectionView()
            }
            .presentationDetents([.medium, .large])
        }
        .catalogueDestinations()
    }

    private var hasActiveFilter: Bool {
        categoryId != nil || settings.selectedVehicleId != nil || !searchText.isEmpty
    }

    private var emptyMessage: String {
        var parts: [String] = []
        if let categoryId, let name = snapshot?.categoryName(id: categoryId) { parts.append(name) }
        if let vehicleName { parts.append(vehicleName) }
        if parts.isEmpty { return "The catalogue is empty." }
        return "Nothing in the catalogue matches \(parts.joined(separator: " · "))."
    }

    private func clearFilters() {
        withAnimation(Motion.standard) {
            categoryId = nil
            settings.selectedVehicleId = nil
            searchText = ""
        }
    }

    // MARK: - Filters

    @ViewBuilder
    private var filters: some View {
        if let snapshot, !snapshot.sortedCategories.isEmpty {
            VStack(spacing: Spacing.xs) {
                ChipRow(
                    items: snapshot.sortedCategories,
                    title: { $0.name },
                    isSelected: { $0.id == categoryId },
                    onSelect: { category in
                        withAnimation(Motion.standard) {
                            categoryId = categoryId == category.id ? nil : category.id
                        }
                    },
                    leading: (
                        title: "All",
                        isSelected: categoryId == nil,
                        action: { withAnimation(Motion.standard) { categoryId = nil } }
                    )
                )

                if let vehicleName {
                    HStack(spacing: Spacing.xs) {
                        Text("Fits \(vehicleName)")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.textTertiary)
                        Button("Clear") {
                            withAnimation(Motion.standard) { settings.selectedVehicleId = nil }
                        }
                        .buttonStyle(TextButtonStyle())
                        .font(TypeScale.caption)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.m)
                }
            }
            .padding(.vertical, Spacing.xs)
            .background(Palette.canvas)

            Hairline()
        }
    }
}
