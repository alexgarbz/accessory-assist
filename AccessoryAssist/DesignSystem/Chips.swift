import SwiftUI

/// Single-select filter chip, 4pt radius, colour-only selected state.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            Text(title)
                .font(TypeScale.label)
                .foregroundStyle(isSelected ? Palette.textOnAccent : Palette.textSecondary)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: TouchTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(isSelected ? Palette.accent : Palette.surface)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.standard, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
    }
}

/// Horizontally scrolling row of filter chips.
struct ChipRow<Item: Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void
    var leading: (title: String, isSelected: Bool, action: () -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                if let leading {
                    FilterChip(title: leading.title, isSelected: leading.isSelected, action: leading.action)
                }
                ForEach(items) { item in
                    FilterChip(
                        title: title(item),
                        isSelected: isSelected(item),
                        action: { onSelect(item) }
                    )
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .scrollClipDisabled()
    }
}

/// Favourite toggle. The filled state is the only place a heart appears.
struct FavouriteButton: View {
    let isFavourite: Bool
    var size: CGFloat = TouchTarget.minimum
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavourite ? "heart.fill" : "heart")
                .font(.system(size: IconSize.medium, weight: .regular))
                .foregroundStyle(isFavourite ? Palette.accent : Palette.textTertiary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.standard, value: isFavourite)
        .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
        .accessibilityAddTraits(isFavourite ? [.isButton, .isSelected] : .isButton)
    }
}

/// Quantity control used in the cart. Large targets — it is operated quickly.
struct QuantityStepper: View {
    let quantity: Int
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    var label: String = "Quantity"

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Image(systemName: quantity <= 1 ? "trash" : "minus")
                    .font(.system(size: IconSize.small, weight: .medium))
                    .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(quantity <= 1 ? Palette.critical : Palette.textPrimary)
            .accessibilityLabel(quantity <= 1 ? "Remove item" : "Decrease quantity")

            Text("\(quantity)")
                .font(TypeScale.price)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 32)
                .accessibilityHidden(true)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: IconSize.small, weight: .medium))
                    .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)
            .accessibilityLabel("Increase quantity")
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(Palette.border, lineWidth: Stroke.thin)
        )
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(label): \(quantity)")
    }
}
