import SwiftUI

/// Hidden developer panel: chooses which catalogue the app reads.
///
/// Production is `main` — approved content. Staging is `staging` — upcoming
/// products, pricing and bundle tests. Custom points at any base URL, which is
/// how this is pointed at a local server during development and how an internal
/// deployment would point it at an authenticated endpoint.
///
/// Switching source clears nothing: each source keeps its own cache directory,
/// so switching back to Production restores the last approved catalogue
/// immediately, with no download and no chance of mixed content.
struct DeveloperSettingsView: View {
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var settings: AppSettings

    @State private var customURLDraft: String = ""
    @State private var customURLError: String?
    @State private var isConfirmingClear = false

    var body: some View {
        List {
            sourceSection
            customSection
            cacheSection
            diagnosticsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Catalogue Source")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { customURLDraft = settings.customSourceURLString }
        .confirmationDialog(
            "Clear cached catalogue?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                catalogue.clearCache()
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app falls back to the catalogue bundled at build time until the next successful refresh.")
        }
    }

    // MARK: - Source

    private var sourceSection: some View {
        Section {
            sourceRow(.production, subtitle: "Approved content · branch \(RemoteCatalogueConfiguration.productionBranch)")
            sourceRow(.staging, subtitle: "Unapproved content · branch \(RemoteCatalogueConfiguration.stagingBranch)")
            if let url = settings.customSourceURL() {
                sourceRow(.custom(url), subtitle: url.absoluteString)
            }
        } header: {
            Text("Source")
        } footer: {
            Text(catalogue.source == .production
                 ? "This device is reading approved production content."
                 : "This device is NOT reading production content. Prices shown may not be approved for sale.")
            .foregroundStyle(catalogue.source == .production ? Palette.textTertiary : Palette.warning)
        }
        .listRowBackground(Palette.surface)
    }

    private func sourceRow(_ source: CatalogueSource, subtitle: String) -> some View {
        Button {
            guard catalogue.source != source else { return }
            settings.catalogueSource = source
            catalogue.switchSource(to: source)
            Haptics.success()
        } label: {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(source.displayName)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                if catalogue.source == source {
                    Image(systemName: "checkmark")
                        .font(.system(size: IconSize.small, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .frame(minHeight: TouchTarget.comfortable)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(catalogue.source == source ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Custom URL

    private var customSection: some View {
        Section {
            TextField("https://example.com/catalogue/", text: $customURLDraft)
                .font(TypeScale.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .onSubmit(applyCustomURL)
                .frame(minHeight: TouchTarget.minimum)

            if let customURLError {
                Text(customURLError)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.critical)
            }

            Button("Use This URL") { applyCustomURL() }
                .font(TypeScale.body)
                .foregroundStyle(Palette.accent)
                .disabled(customURLDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Custom Base URL")
        } footer: {
            Text("The base URL must contain version.json, catalogue.json, bundles.json, announcements.json and an images/ directory. A trailing slash is added if missing.")
        }
        .listRowBackground(Palette.surface)
    }

    private func applyCustomURL() {
        settings.customSourceURLString = customURLDraft
        guard let url = settings.customSourceURL() else {
            customURLError = "Enter a full http or https URL."
            Haptics.error()
            return
        }
        customURLError = nil
        settings.catalogueSource = .custom(url)
        catalogue.switchSource(to: .custom(url))
        Haptics.success()
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section {
            LabeledContent {
                Text(catalogue.cacheSizeDescription())
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textTertiary)
            } label: {
                Text("Cache Size")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
            }

            Button("Clear Cached Catalogue") { isConfirmingClear = true }
                .font(TypeScale.body)
                .foregroundStyle(Palette.critical)
        } header: {
            Text("Cache")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            DetailRow(label: "Base URL", value: catalogue.source.baseURL.absoluteString, isMonospaced: true)
            DetailRow(label: "Cache key", value: catalogue.source.cacheKey, isMonospaced: true)
            if let snapshot = catalogue.snapshot {
                DetailRow(label: "Environment", value: snapshot.catalogue.environment)
                DetailRow(label: "Schema", value: "\(snapshot.catalogue.schemaVersion)")
                DetailRow(label: "Products", value: "\(snapshot.catalogue.products.count)")
                DetailRow(label: "Bundles", value: "\(snapshot.bundleCatalogue.bundles.count)")
            }
        } header: {
            Text("Diagnostics")
        }
        .listRowBackground(Palette.surface)
    }
}
