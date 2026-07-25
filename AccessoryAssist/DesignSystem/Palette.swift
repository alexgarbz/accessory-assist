import SwiftUI

/// Semantic colour tokens.
///
/// Derived from the Tesla design guidelines: a white canvas, three greys of
/// text hierarchy, hairline dividers, and one chromatic colour — Electric Blue
/// — reserved for primary action. Nothing in the app hard-codes a colour; if a
/// value is needed that is not here, the token set is what changes.
///
/// Dark appearance is built on Carbon Dark (#171A20), the same near-black the
/// guidelines specify for dark surfaces, with text and dividers inverted to
/// preserve the identical contrast relationships rather than a different mood.
///
/// Deviation from the source guidelines, noted deliberately: the guidelines
/// avoid semantic status colour entirely, which suits a marketing site. This is
/// an operational tool where "this SKU is discontinued" and "you are on stale
/// data" must be unmissable, so a warning and a critical token exist. Both are
/// desaturated, used only for status, and never for decoration.
enum Palette {

    // MARK: - Surfaces

    /// Page background. Pure white in light, Carbon Dark in dark.
    static let canvas = Color(light: 0xFFFFFF, dark: 0x171A20)
    /// Cards and grouped rows. Light Ash in light, one step up from canvas in dark.
    static let surface = Color(light: 0xF4F4F4, dark: 0x1F2229)
    /// A second surface level for controls sitting on `surface`.
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x272B33)
    /// Full-bleed dark surface used by scan mode's chrome.
    static let inverseCanvas = Color(light: 0x171A20, dark: 0x000000)

    // MARK: - Text

    /// Headings, product names, prices.
    static let textPrimary = Color(light: 0x171A20, dark: 0xFFFFFF)
    /// Body copy and secondary detail.
    static let textSecondary = Color(light: 0x393C41, dark: 0xC7CAD0)
    /// Metadata, captions, supporting labels.
    static let textTertiary = Color(light: 0x5C5E62, dark: 0x9BA0A8)
    /// Placeholders and disabled text.
    static let textPlaceholder = Color(light: 0x8E8E8E, dark: 0x74797F)
    /// Text drawn on Electric Blue.
    static let textOnAccent = Color.white
    /// Text drawn on `inverseCanvas`.
    static let textInverse = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    // MARK: - Lines

    /// Hairline divider between rows.
    static let divider = Color(light: 0xEEEEEE, dark: 0x2E323A)
    /// Slightly stronger line for control borders.
    static let border = Color(light: 0xD0D1D2, dark: 0x3C414A)

    // MARK: - Action

    /// Electric Blue. Primary actions only — never decoration.
    static let accent = Color(light: 0x3E6AE1, dark: 0x5A82EA)
    /// Pressed state for accent fills.
    static let accentPressed = Color(light: 0x2F55BE, dark: 0x4A70D4)
    /// Tinted background for selected chips and rows.
    static let accentSubtle = Color(light: 0xEAEFFC, dark: 0x1E2740)

    // MARK: - Status

    static let warning = Color(light: 0x8A5A00, dark: 0xE0A93C)
    static let warningSubtle = Color(light: 0xFBF3E4, dark: 0x2C2417)
    static let critical = Color(light: 0xA3271C, dark: 0xE8776B)
    static let criticalSubtle = Color(light: 0xFBECEA, dark: 0x2E1A18)
    static let positive = Color(light: 0x1F6B45, dark: 0x5FBF8E)

    // MARK: - Scan mode

    /// Barcode bars. Pure black on pure white, at any appearance — scanner
    /// contrast is not a place for theming.
    static let barcodeInk = Color.black
    static let barcodePaper = Color.white
}

extension Color {

    /// Build a colour from light and dark hex values.
    ///
    /// Using a dynamic `UIColor` rather than two asset entries keeps every
    /// token visible in one file, which is what makes the palette auditable.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
