import Foundation
import SwiftUI

/// User-visible and developer-only preferences.
///
/// The catalogue source lives here rather than in `CatalogueService` so that the
/// choice survives relaunch and can be changed from the hidden developer panel
/// without the service knowing anything about persistence.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let source = "settings.catalogueSource.v1"
        static let customURL = "settings.customCatalogueURL.v1"
        static let developerUnlocked = "settings.developerUnlocked.v1"
        static let selectedVehicle = "settings.selectedVehicleId.v1"
        static let scanBrightness = "settings.scanBrightness.v1"
        static let hapticsEnabled = "settings.hapticsEnabled.v1"
    }

    /// Where catalogue content is loaded from.
    @Published var catalogueSource: CatalogueSource {
        didSet { defaults.set(catalogueSource.storageValue, forKey: Key.source) }
    }

    /// Last custom URL typed into the developer panel, kept so switching back
    /// and forth does not mean retyping it.
    @Published var customSourceURLString: String {
        didSet { defaults.set(customSourceURLString, forKey: Key.customURL) }
    }

    /// Developer settings stay hidden until unlocked from the Settings footer.
    @Published var isDeveloperUnlocked: Bool {
        didSet { defaults.set(isDeveloperUnlocked, forKey: Key.developerUnlocked) }
    }

    /// Vehicle filter applied across Home and the catalogue. `nil` means all.
    @Published var selectedVehicleId: String? {
        didSet { defaults.set(selectedVehicleId, forKey: Key.selectedVehicle) }
    }

    /// Screen brightness used while scan mode is open. Full brightness reads
    /// most reliably, but some counters prefer it a little lower.
    @Published var scanBrightness: Double {
        didSet { defaults.set(scanBrightness, forKey: Key.scanBrightness) }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled)
            Haptics.isEnabled = hapticsEnabled
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSource = defaults.string(forKey: Key.source) ?? CatalogueSource.production.storageValue
        catalogueSource = CatalogueSource(storageValue: storedSource) ?? .production
        customSourceURLString = defaults.string(forKey: Key.customURL) ?? ""
        isDeveloperUnlocked = defaults.bool(forKey: Key.developerUnlocked)
        selectedVehicleId = defaults.string(forKey: Key.selectedVehicle)
        let storedBrightness = defaults.double(forKey: Key.scanBrightness)
        scanBrightness = storedBrightness > 0 ? storedBrightness : 1.0
        let storedHaptics = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        hapticsEnabled = storedHaptics
        Haptics.isEnabled = storedHaptics
    }

    /// Parse the custom URL field, normalising a missing trailing slash so that
    /// relative file names resolve correctly.
    func customSourceURL() -> URL? {
        let trimmed = customSourceURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalised = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        guard let url = URL(string: normalised), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return nil
        }
        return url
    }

    /// Version string shown in Settings and used as the developer unlock target.
    var appVersionDescription: String {
        let info = Foundation.Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
