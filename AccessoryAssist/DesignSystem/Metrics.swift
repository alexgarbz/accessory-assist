import SwiftUI

/// Spacing tokens on an 8pt base, as specified.
///
/// Whitespace is the primary structuring device in this design language, so
/// these values are used rather than ad-hoc padding anywhere in the app.
enum Spacing {
    /// 4pt — inside a control, between an icon and its label.
    static let xxs: CGFloat = 4
    /// 8pt — between tightly related lines of text.
    static let xs: CGFloat = 8
    /// 12pt — inside cards.
    static let s: CGFloat = 12
    /// 16pt — the standard screen margin.
    static let m: CGFloat = 16
    /// 24pt — between distinct groups.
    static let l: CGFloat = 24
    /// 32pt — between major sections.
    static let xl: CGFloat = 32
    /// 48pt — around empty states and headline moments.
    static let xxl: CGFloat = 48
}

/// Corner radius tokens.
///
/// 4pt on every interactive element, exactly as specified — precise rather than
/// playful. 12pt on large image surfaces only. Nothing is a pill.
enum Radius {
    /// Sharp. The default.
    static let none: CGFloat = 0
    /// 4pt — buttons, fields, chips.
    static let control: CGFloat = 4
    /// 12pt — image cards and other large surfaces.
    static let card: CGFloat = 12
}

/// Line weights. Hairlines only; the app has no heavy rules.
enum Stroke {
    static let hairline: CGFloat = 1 / 3
    static let thin: CGFloat = 1
}

/// Icon sizing. SF Symbols only, at three sizes.
enum IconSize {
    /// 16pt — inline with text.
    static let small: CGFloat = 16
    /// 20pt — standard control icon.
    static let medium: CGFloat = 20
    /// 28pt — primary navigation and scan controls.
    static let large: CGFloat = 28
}

/// Touch target floors. The 44pt HIG minimum is the floor, not the target:
/// this app is used one-handed, at speed, often while holding something else.
enum TouchTarget {
    static let minimum: CGFloat = 44
    static let comfortable: CGFloat = 52
    /// Scan mode's Previous/Next controls, hit without looking.
    static let scanControl: CGFloat = 72
}

/// Motion tokens.
///
/// One duration — 0.33s — as specified, so every transition in the app has the
/// same tempo. All motion respects Reduce Motion via `Motion.standard`, which
/// collapses to no animation when the accessibility setting is on.
enum Motion {
    static let duration: TimeInterval = 0.33

    static var standard: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: duration)
    }

    /// Snappier variant for direct manipulation, e.g. stepping a barcode.
    static var immediate: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.18)
    }
}

/// Fixed aspect ratios for product imagery, so a grid never jumps as images
/// load at different intrinsic sizes.
enum ImageRatio {
    static let product: CGFloat = 4.0 / 3.0
    static let hero: CGFloat = 16.0 / 9.0
    static let thumbnail: CGFloat = 1.0
}
