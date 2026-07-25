import SwiftUI

/// Composition root.
///
/// Services are constructed once here and injected as environment objects.
/// `CatalogueService` publishes cached content synchronously during init, so the
/// first frame already has a catalogue in it; the network check starts after the
/// UI is on screen.
@main
struct AccessoryAssistApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var catalogue: CatalogueService
    @StateObject private var imageStore: ImageStore
    @StateObject private var cart = CartStore()
    @StateObject private var favourites = FavouritesStore()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        let imageStore = ImageStore(source: settings.catalogueSource)
        let catalogue = CatalogueService(
            source: settings.catalogueSource,
            imageStore: imageStore
        )
        _settings = StateObject(wrappedValue: settings)
        _imageStore = StateObject(wrappedValue: imageStore)
        _catalogue = StateObject(wrappedValue: catalogue)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(catalogue)
                .environmentObject(imageStore)
                .environmentObject(cart)
                .environmentObject(favourites)
                .tint(Palette.accent)
                .task {
                    // Launch check: compares version.json against the cached
                    // version and downloads only when it differs.
                    catalogue.refresh()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // A shift can run all day. Re-check on return to foreground so a
            // price published at lunchtime is picked up without a relaunch.
            if newPhase == .active {
                catalogue.refresh()
            }
        }
    }
}
