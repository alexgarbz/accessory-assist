import SwiftUI

/// Five tabs, each with its own navigation stack.
///
/// Tab order follows how often staff reach for each one: Home first, then the
/// full catalogue, favourites, the cart, and settings last. The cart carries a
/// live badge because its contents are the sale in progress.
struct RootView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var settings: AppSettings

    @State private var selection: Tab = .home

    enum Tab: Hashable {
        case home, catalogue, favourites, cart, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(Tab.home)

            NavigationStack {
                CatalogueView()
            }
            .tabItem {
                Label("Catalogue", systemImage: "square.grid.2x2")
            }
            .tag(Tab.catalogue)

            NavigationStack {
                FavouritesView()
            }
            .tabItem {
                Label("Favourites", systemImage: "heart")
            }
            .tag(Tab.favourites)

            NavigationStack {
                CartView()
            }
            .tabItem {
                Label("Cart", systemImage: "cart")
            }
            .badge(cart.itemCount)
            .tag(Tab.cart)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
        .tint(Palette.accent)
        .overlay(alignment: .top) {
            // A device left on staging is a way to quote unapproved prices.
            // It says so, permanently, until it is switched back.
            if catalogue.source != .production {
                StagingBadge(sourceName: catalogue.source.displayName)
            }
        }
    }
}

/// Persistent marker shown whenever the app is not reading production content.
struct StagingBadge: View {
    let sourceName: String

    var body: some View {
        Text("\(sourceName.uppercased()) CATALOGUE")
            .font(.system(size: 10, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Palette.textOnAccent)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Palette.warning)
            )
            .padding(.top, Spacing.xxs)
            .allowsHitTesting(false)
            .accessibilityLabel("Warning: reading \(sourceName) catalogue, not production")
    }
}
