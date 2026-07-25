import SwiftUI

/// Home is optimised for one thing: getting from opening the app to a barcode
/// on screen in a few seconds.
///
/// Hierarchy, top to bottom: search, vehicle filter, favourites, featured
/// accessories, bundles, current cart. Search sits above everything because it
/// is the fastest route for staff who already know the product; the vehicle
/// filter is next because it is the fastest route for staff who do not.
///
/// Typing in the search field replaces the sections with results in place —
/// no push, no second screen, no keyboard dismissal between query and result.
struct HomeView: View {
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }

    private var filteredProducts: [Product] {
        guard let snapshot else { return [] }
        return snapshot.sellableProducts.filter { $0.fits(vehicleId: settings.selectedVehicleId) }
    }

    private var searchResults: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let snapshot else { return [] }
        // Search deliberately ignores the vehicle filter: staff searching a
        // specific SKU must always find it, even with a filter left on.
        return snapshot.catalogue.products
            .filter { $0.matches(query: query) }
            .sorted { lhs, rhs in
                let lhsExact = lhs.sku.lowercased() == query.lowercased()
                let rhsExact = rhs.sku.lowercased() == query.lowercased()
                if lhsExact != rhsExact { return lhsExact }
                if lhs.status.isSellable != rhs.status.isSellable { return lhs.status.isSellable }
                return lhs.name < rhs.name
            }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                searchField
                    .padding(.horizontal, Spacing.m)

                if isSearching {
                    SearchResultsSection(
                        query: searchText,
                        results: searchResults,
                        snapshot: snapshot
                    )
                } else {
                    statusSection
                    announcementsSection
                    vehicleSection
                    favouritesSection
                    featuredSection
                    bundlesSection
                    cartSection
                }
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.canvas)
        .navigationTitle("Accessory Assist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Accessory Assist")
                    .wordmarkStyle()
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .refreshable {
            await catalogue.refreshAndWait()
        }
        .catalogueDestinations()
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: IconSize.medium, weight: .regular))
                .foregroundStyle(Palette.textPlaceholder)

            TextField("Search name or SKU", text: $searchText)
                .font(TypeScale.body)
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .accessibilityLabel("Search accessories by name or SKU")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: IconSize.medium))
                        .foregroundStyle(Palette.textPlaceholder)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.s)
        .frame(height: TouchTarget.comfortable)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.surface)
        )
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        if catalogue.snapshot == nil {
            ErrorStateView(
                title: "Catalogue Unavailable",
                message: catalogue.lastError?.localizedDescription
                    ?? "No catalogue has been downloaded to this device yet.",
                retryTitle: "Refresh Catalogue",
                retry: { catalogue.refresh(force: true) }
            )
        } else if catalogue.isUsingOfflineData {
            StatusBanner(
                title: catalogue.isOffline ? "Using Offline Data" : "Catalogue Not Up To Date",
                message: offlineMessage,
                tone: .warning,
                actionTitle: "Refresh",
                action: { catalogue.refresh(force: true) },
                systemImage: catalogue.isOffline ? "wifi.slash" : "clock.arrow.circlepath"
            )
            .padding(.horizontal, Spacing.m)
        }
    }

    private var offlineMessage: String {
        if let updated = catalogue.lastSuccessfulUpdate {
            return "Showing the catalogue last updated \(Format.relative(updated))."
        }
        return "Showing the catalogue bundled with the app. Prices may be out of date."
    }

    @ViewBuilder
    private var announcementsSection: some View {
        let live = snapshot?.liveAnnouncements() ?? []
        let pinned = live.filter(\.pinned)
        if !pinned.isEmpty {
            VStack(spacing: Spacing.xs) {
                ForEach(pinned) { announcement in
                    StatusBanner(
                        title: announcement.title,
                        message: announcement.body,
                        tone: announcement.severity == .info ? .info : .warning,
                        systemImage: announcement.severity == .critical
                            ? "exclamationmark.triangle"
                            : "megaphone"
                    )
                }
            }
            .padding(.horizontal, Spacing.m)
        }
    }

    @ViewBuilder
    private var vehicleSection: some View {
        if let snapshot, !snapshot.selectableVehicles.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(
                    title: "Vehicle",
                    subtitle: settings.selectedVehicleId == nil
                        ? "Filter the catalogue to one vehicle"
                        : "Showing accessories that fit \(snapshot.vehicle(id: settings.selectedVehicleId ?? "")?.name ?? "")"
                )
                .padding(.horizontal, Spacing.m)

                ChipRow(
                    items: snapshot.selectableVehicles,
                    title: { $0.name },
                    isSelected: { $0.id == settings.selectedVehicleId },
                    onSelect: { vehicle in
                        withAnimation(Motion.standard) {
                            settings.selectedVehicleId = settings.selectedVehicleId == vehicle.id ? nil : vehicle.id
                        }
                    },
                    leading: (
                        title: "All",
                        isSelected: settings.selectedVehicleId == nil,
                        action: {
                            withAnimation(Motion.standard) { settings.selectedVehicleId = nil }
                        }
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var favouritesSection: some View {
        let items = favourites.products(in: snapshot)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Favourites", subtitle: "\(items.count) saved")
                    .padding(.horizontal, Spacing.m)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        ForEach(items) { product in
                            ProductCard(
                                product: product,
                                snapshot: snapshot,
                                isFavourite: true,
                                onToggleFavourite: { favourites.toggle(product.id) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private var featuredSection: some View {
        let featured = filteredProducts.filter(\.featured)
        if !featured.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Featured Accessories") {
                    NavigationLink(value: CatalogueRoute.all) {
                        Text("All")
                            .font(TypeScale.button)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(.horizontal, Spacing.m)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        ForEach(featured) { product in
                            ProductCard(
                                product: product,
                                snapshot: snapshot,
                                isFavourite: favourites.contains(product.id),
                                onToggleFavourite: { favourites.toggle(product.id) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                }
                .scrollClipDisabled()
            }
        } else if snapshot != nil {
            EmptyStateView(
                title: "No featured accessories",
                message: settings.selectedVehicleId == nil
                    ? "Nothing is featured in the current catalogue."
                    : "Nothing is featured for this vehicle. Clear the filter to see everything.",
                systemImage: "star",
                actionTitle: settings.selectedVehicleId == nil ? nil : "Clear Filter",
                action: settings.selectedVehicleId == nil ? nil : { settings.selectedVehicleId = nil }
            )
        }
    }

    @ViewBuilder
    private var bundlesSection: some View {
        let bundles = (snapshot?.activeBundles ?? [])
            .filter { $0.fits(vehicleId: settings.selectedVehicleId) }
        if !bundles.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Bundles", subtitle: "Pre-priced accessory groups")
                    .padding(.horizontal, Spacing.m)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        ForEach(bundles) { bundle in
                            BundleCard(bundle: bundle, snapshot: snapshot)
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private var cartSection: some View {
        if !cart.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Current Cart", subtitle: "\(cart.itemCount) item\(cart.itemCount == 1 ? "" : "s")")
                    .padding(.horizontal, Spacing.m)

                NavigationLink(value: CatalogueRoute.cart) {
                    HStack(spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(Format.price(cart.total(in: snapshot), currency: snapshot?.currency ?? "USD"))
                                .font(TypeScale.subheading)
                                .foregroundStyle(Palette.textPrimary)
                            Text("\(cart.distinctItemCount) line\(cart.distinctItemCount == 1 ? "" : "s") · tap to open")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: IconSize.small, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .cardSurface()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.m)
                .accessibilityLabel("Current cart, \(cart.itemCount) items, \(Format.price(cart.total(in: snapshot), currency: snapshot?.currency ?? "USD"))")
            }
        }
    }
}

/// Inline search results, shown in place of the Home sections while a query is
/// active. Exact SKU matches sort to the top.
struct SearchResultsSection: View {
    let query: String
    let results: [Product]
    let snapshot: CatalogueSnapshot?

    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(
                title: "Results",
                subtitle: "\(results.count) match\(results.count == 1 ? "" : "es") for “\(query)”"
            )
            .padding(.horizontal, Spacing.m)

            if results.isEmpty {
                EmptyStateView(
                    title: "No matches",
                    message: "Nothing in the current catalogue matches “\(query)”. Check the SKU, or search by product name.",
                    systemImage: "magnifyingglass"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(results) { product in
                        ProductRow(
                            product: product,
                            snapshot: snapshot,
                            isFavourite: favourites.contains(product.id),
                            quantityInCart: cart.quantity(of: product.id),
                            onToggleFavourite: { favourites.toggle(product.id) },
                            onAdd: { cart.add(product) }
                        )
                        .padding(.horizontal, Spacing.m)

                        if product.id != results.last?.id {
                            Hairline(inset: Spacing.m + 68 + Spacing.m)
                        }
                    }
                }
            }
        }
    }
}
