import SwiftUI

/// Settings.
///
/// Three groups: the catalogue (what is loaded and when it last changed), scan
/// mode (how the barcode screen behaves), and about (which build this is).
/// Developer settings stay hidden until the build row is tapped seven times —
/// staff never need them, and a visible "switch to staging" control on a shop
/// floor is a way to sell from unapproved pricing by accident.
struct SettingsView: View {
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var favourites: FavouritesStore

    @State private var unlockTapCount = 0
    @State private var showsUnlockConfirmation = false

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }

    var body: some View {
        List {
            catalogueSection
            scanSection
            dataSection
            aboutSection

            if settings.isDeveloperUnlocked {
                developerSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Developer settings unlocked", isPresented: $showsUnlockConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Catalogue source switching is now available at the bottom of Settings.")
        }
        .catalogueDestinations()
    }

    // MARK: - Catalogue

    private var catalogueSection: some View {
        Section {
            NavigationLink(value: CatalogueRoute.status) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Catalogue Status")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textPrimary)
                    Text(catalogue.statusSummary)
                        .font(TypeScale.caption)
                        .foregroundStyle(statusColor)
                }
                .padding(.vertical, Spacing.xxs)
            }

            LabeledContent {
                Text(Format.lastUpdated(catalogue.lastSuccessfulUpdate))
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text("Last Updated")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
            }

            Button {
                Haptics.impact()
                catalogue.refresh(force: true)
            } label: {
                HStack {
                    Text(catalogue.isRefreshing ? "Refreshing…" : "Refresh Catalogue")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.accent)
                    Spacer()
                    if catalogue.isRefreshing {
                        ProgressView()
                    }
                }
                .frame(minHeight: TouchTarget.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(catalogue.isRefreshing)
        } header: {
            Text("Catalogue")
        } footer: {
            Text(catalogueFooter)
        }
        .listRowBackground(Palette.surface)
    }

    private var statusColor: Color {
        if catalogue.lastError != nil { return Palette.warning }
        if catalogue.snapshot?.isSeed == true { return Palette.warning }
        return Palette.textTertiary
    }

    private var catalogueFooter: String {
        var parts: [String] = []
        if let version = catalogue.catalogueVersion {
            parts.append("Version \(version)")
        }
        parts.append("Source: \(catalogue.source.displayName)")
        if let count = snapshot?.sellableProducts.count {
            parts.append("\(count) active products")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Scan mode

    private var scanSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Scan Brightness")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text("\(Int(settings.scanBrightness * 100))%")
                        .font(TypeScale.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
                Slider(value: $settings.scanBrightness, in: 0.4...1.0, step: 0.05)
                    .tint(Palette.accent)
                    .accessibilityLabel("Scan mode screen brightness")
                    .accessibilityValue("\(Int(settings.scanBrightness * 100)) percent")
            }
            .padding(.vertical, Spacing.xxs)

            Toggle(isOn: $settings.hapticsEnabled) {
                Text("Haptic Feedback")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.accent)
        } header: {
            Text("Scan Mode")
        } footer: {
            Text("Scan mode raises the screen to this brightness and prevents the display sleeping. The previous brightness is restored on exit.")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            LabeledContent {
                Text("\(favourites.count)")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
            } label: {
                Text("Favourites")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
            }

            LabeledContent {
                Text("\(cart.itemCount)")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
            } label: {
                Text("Items in Cart")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
            }

            LabeledContent {
                Text(catalogue.cacheSizeDescription())
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
            } label: {
                Text("Offline Cache")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
            }
        } header: {
            Text("On This Device")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Button {
                registerUnlockTap()
            } label: {
                LabeledContent {
                    Text(settings.appVersionDescription)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textTertiary)
                } label: {
                    Text("Version")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(minHeight: TouchTarget.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Tap seven times to unlock developer settings")
        } header: {
            Text("About")
        } footer: {
            Text("Internal tool for Tesla retail staff. Not for customer use. No payment is taken in this app.")
        }
        .listRowBackground(Palette.surface)
    }

    private func registerUnlockTap() {
        guard !settings.isDeveloperUnlocked else { return }
        unlockTapCount += 1
        if unlockTapCount >= 7 {
            settings.isDeveloperUnlocked = true
            unlockTapCount = 0
            showsUnlockConfirmation = true
            Haptics.success()
        } else if unlockTapCount >= 4 {
            Haptics.selection()
        }
    }

    // MARK: - Developer

    private var developerSection: some View {
        Section {
            NavigationLink {
                DeveloperSettingsView()
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Catalogue Source")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textPrimary)
                    Text(catalogue.source.displayName)
                        .font(TypeScale.caption)
                        .foregroundStyle(catalogue.source == .production ? Palette.textTertiary : Palette.warning)
                }
                .padding(.vertical, Spacing.xxs)
            }

            Button("Hide Developer Settings") {
                settings.isDeveloperUnlocked = false
                Haptics.selection()
            }
            .font(TypeScale.body)
            .foregroundStyle(Palette.accent)
        } header: {
            Text("Developer")
        } footer: {
            Text("Staging content is unapproved. Return to Production before selling from this device.")
        }
        .listRowBackground(Palette.surface)
    }
}
