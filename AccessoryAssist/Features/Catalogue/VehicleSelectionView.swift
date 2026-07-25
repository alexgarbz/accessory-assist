import SwiftUI

/// Vehicle selection.
///
/// The filter that matters most in a store: a customer arrives with one car,
/// and everything that does not fit it is noise. Each row carries the count of
/// accessories that fit, so staff know what they are about to see.
struct VehicleSelectionView: View {
    @EnvironmentObject private var catalogue: CatalogueService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }

    private func count(for vehicleId: String?) -> Int {
        guard let snapshot else { return 0 }
        return snapshot.sellableProducts.filter { $0.fits(vehicleId: vehicleId) }.count
    }

    var body: some View {
        List {
            Section {
                row(
                    title: "All Vehicles",
                    subtitle: "\(count(for: nil)) accessories",
                    isSelected: settings.selectedVehicleId == nil
                ) {
                    select(nil)
                }
            }

            Section("Vehicle") {
                ForEach(snapshot?.selectableVehicles ?? []) { vehicle in
                    row(
                        title: vehicle.name,
                        subtitle: "\(count(for: vehicle.id)) accessories",
                        isSelected: settings.selectedVehicleId == vehicle.id
                    ) {
                        select(vehicle.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(TypeScale.button)
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private func row(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(TypeScale.productName)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: IconSize.small, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .frame(minHeight: TouchTarget.comfortable)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.surface)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ vehicleId: String?) {
        withAnimation(Motion.standard) {
            settings.selectedVehicleId = vehicleId
        }
        Haptics.selection()
        dismiss()
    }
}
