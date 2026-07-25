import SwiftUI

/// Loading, empty, offline and error presentations.
///
/// Every screen that can be in one of these states uses these views, so a
/// failure looks the same wherever it happens and always names the recovery
/// action in operational language.

// MARK: - Loading

/// Placeholder shown while the first catalogue load is in flight.
///
/// A skeleton rather than a spinner: the layout does not shift when content
/// arrives, which matters on a screen staff are already reaching towards.
struct LoadingStateView: View {
    var label: String = "Loading catalogue…"
    var rowCount: Int = 5

    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.surface)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.surface)
                            .frame(height: 14)
                            .frame(maxWidth: .infinity)
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.surface)
                            .frame(width: 120, height: 12)
                    }
                }
            }
        }
        .opacity(isPulsing ? 0.55 : 1)
        .animation(
            UIAccessibility.isReduceMotionEnabled
                ? nil
                : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = true }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Empty

/// Neutral empty state: what is missing and, where one exists, the way out.
struct EmptyStateView: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.textPlaceholder)
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(TypeScale.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle(fillsWidth: false))
                    .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Error

/// Failure state with the reason and a retry.
struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)?
    var detail: [String] = []

    @State private var isShowingDetail = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.warning)
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(TypeScale.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(PrimaryButtonStyle(fillsWidth: false))
                    .padding(.top, Spacing.xs)
            }
            if !detail.isEmpty {
                Button(isShowingDetail ? "Hide Detail" : "Show Detail") {
                    withAnimation(Motion.standard) { isShowingDetail.toggle() }
                }
                .buttonStyle(TextButtonStyle())

                if isShowingDetail {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(detail, id: \.self) { line in
                            Text(line)
                                .font(TypeScale.mono)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .cardSurface()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.l)
    }
}

// MARK: - Offline / status banner

/// Inline status strip for stale or failed catalogue data.
///
/// Deliberately not a modal or a toast: staff need to keep working with the
/// data they have, and the banner has to stay visible while they do.
struct StatusBanner: View {
    enum Tone {
        case info
        case warning
        case critical

        var foreground: Color {
            switch self {
            case .info: return Palette.textSecondary
            case .warning: return Palette.warning
            case .critical: return Palette.critical
            }
        }

        var background: Color {
            switch self {
            case .info: return Palette.surface
            case .warning: return Palette.warningSubtle
            case .critical: return Palette.criticalSubtle
            }
        }

        var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.circle"
            case .critical: return "exclamationmark.triangle"
            }
        }
    }

    let title: String
    var message: String?
    var tone: Tone = .info
    var actionTitle: String?
    var action: (() -> Void)?
    var systemImage: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: systemImage ?? tone.systemImage)
                .font(.system(size: IconSize.small, weight: .medium))
                .foregroundStyle(tone.foreground)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(TypeScale.label)
                    .foregroundStyle(tone.foreground)
                if let message {
                    Text(message)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Spacing.xs)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(TextButtonStyle())
                    .font(TypeScale.label)
            }
        }
        .padding(Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(tone.background)
        )
        .accessibilityElement(children: .combine)
    }
}
