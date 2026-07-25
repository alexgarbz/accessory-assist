import SwiftUI

/// Type tokens.
///
/// The guidelines specify Universal Sans at fixed pixel sizes with only two
/// weights, 400 and 500. Universal Sans is not licensed for redistribution and
/// fixed pixel sizes would break Dynamic Type, so this system keeps what
/// matters — the restraint — and expresses it natively:
///
///  * SF Pro, the system face, which shares Universal Sans's engineered,
///    unembellished character and is what makes the app feel native.
///  * Regular and Medium only. No bold, no light, no italic anywhere.
///  * Sizes bound to iOS text styles, so every label scales with Dynamic Type
///    while the hierarchy between them stays fixed.
///  * Default tracking throughout, exactly as specified — no negative tracking
///    on headings. The one exception is the wordmark, which is letter-spaced.
enum TypeScale {

    /// Screen title. The largest type in the app.
    static let title = Font.system(.largeTitle, design: .default, weight: .medium)
    /// Section heading inside a screen.
    static let heading = Font.system(.title2, design: .default, weight: .medium)
    /// Card and group heading.
    static let subheading = Font.system(.title3, design: .default, weight: .medium)
    /// Product name in a row or card.
    static let productName = Font.system(.headline, design: .default, weight: .medium)
    /// Price and other emphasised numerics.
    static let price = Font.system(.body, design: .default, weight: .medium)
    /// Default body copy.
    static let body = Font.system(.body, design: .default, weight: .regular)
    /// Supporting copy under a title.
    static let secondary = Font.system(.subheadline, design: .default, weight: .regular)
    /// Metadata: compatibility, category, timestamps.
    static let caption = Font.system(.footnote, design: .default, weight: .regular)
    /// Small label, e.g. chip text and status pills.
    static let label = Font.system(.footnote, design: .default, weight: .medium)
    /// Button text.
    static let button = Font.system(.body, design: .default, weight: .medium)
    /// SKU and other machine-readable strings. Monospaced digits keep columns
    /// of SKUs aligned when scanning down a list.
    static let mono = Font.system(.footnote, design: .monospaced, weight: .regular)
    /// The SKU printed under a barcode in scan mode.
    static let scanSKU = Font.system(size: 26, weight: .medium, design: .monospaced)
    /// Product name in scan mode, read at arm's length.
    static let scanTitle = Font.system(size: 20, weight: .regular, design: .default)
}

extension View {
    /// The app wordmark: the one place letter-spacing is applied, mirroring the
    /// spaced TESLA wordmark in the guidelines.
    func wordmarkStyle() -> some View {
        self.font(.system(.subheadline, design: .default, weight: .medium))
            .tracking(4)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textPrimary)
    }
}
