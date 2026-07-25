import SwiftUI

/// Card surface: a fill and a radius, no border and no shadow.
///
/// The guidelines are unambiguous that elevation is not communicated with
/// shadow. Grouping here comes from the surface fill and the space around it.
struct CardSurface: ViewModifier {
    var padding: CGFloat = Spacing.m
    var radius: CGFloat = Radius.card
    var fill: Color = Palette.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
    }
}

extension View {
    func cardSurface(
        padding: CGFloat = Spacing.m,
        radius: CGFloat = Radius.card,
        fill: Color = Palette.surface
    ) -> some View {
        modifier(CardSurface(padding: padding, radius: radius, fill: fill))
    }
}

/// Hairline rule. Used between rows in a list, never as decoration.
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: Stroke.thin)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Section header: a title, an optional count, and an optional trailing action.
///
/// Section titles carry the information hierarchy on Home and in the catalogue,
/// so they are consistent everywhere rather than restyled per screen.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(TypeScale.heading)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: Spacing.s)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// Small status pill, e.g. "Discontinued" or "Staging".
struct StatusPill: View {
    enum Tone {
        case neutral
        case accent
        case warning
        case critical
        case positive

        var foreground: Color {
            switch self {
            case .neutral: return Palette.textSecondary
            case .accent: return Palette.accent
            case .warning: return Palette.warning
            case .critical: return Palette.critical
            case .positive: return Palette.positive
            }
        }

        var background: Color {
            switch self {
            case .neutral: return Palette.surface
            case .accent: return Palette.accentSubtle
            case .warning: return Palette.warningSubtle
            case .critical: return Palette.criticalSubtle
            case .positive: return Palette.surface
            }
        }
    }

    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(text)
                .font(TypeScale.label)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(tone.background)
        )
    }
}

/// A labelled key/value row, used for specifications and status detail.
struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Palette.textPrimary
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: Spacing.m)
            Text(value)
                .font(isMonospaced ? TypeScale.mono : TypeScale.body)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }
}
