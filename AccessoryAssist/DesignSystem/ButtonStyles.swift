import SwiftUI

/// Primary action. Electric Blue fill, white label, 4pt radius.
///
/// At most one of these is visible per screen — the guidelines are explicit
/// that competing calls to action dilute the hierarchy. Pressed state is a
/// colour change only: no scale, no translation, no shadow.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(Palette.textOnAccent)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: TouchTarget.comfortable)
            .padding(.horizontal, Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? Palette.accentPressed : Palette.accent)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Motion.standard, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Secondary action. Surface fill with a hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: TouchTarget.comfortable)
            .padding(.horizontal, Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? Palette.surface : Palette.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Palette.border, lineWidth: Stroke.thin)
            )
            .animation(Motion.standard, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Text-only action for tertiary links and inline controls.
struct TextButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(configuration.isPressed ? tint.opacity(0.6) : tint)
            .frame(minHeight: TouchTarget.minimum)
            .animation(Motion.standard, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Destructive text action, e.g. clearing the cart.
struct DestructiveTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(configuration.isPressed ? Palette.critical.opacity(0.6) : Palette.critical)
            .frame(minHeight: TouchTarget.minimum)
            .animation(Motion.standard, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Square icon button used in toolbars and on image overlays.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = TouchTarget.minimum
    var tint: Color = Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: IconSize.medium, weight: .medium))
            .foregroundStyle(configuration.isPressed ? tint.opacity(0.5) : tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? Palette.surface : Color.clear)
            )
            .animation(Motion.standard, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Full-width row that behaves like a button — used for list rows that push a
/// detail screen, giving a clear pressed state without a disclosure animation.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.surface : Color.clear)
            .animation(Motion.immediate, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
