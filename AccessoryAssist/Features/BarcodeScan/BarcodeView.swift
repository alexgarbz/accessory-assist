import SwiftUI

/// Draws a Code 128 symbol.
///
/// Bars are rendered with antialiasing disabled, so every module edge lands on
/// a hard pixel boundary. A softened edge is the usual reason a screen-displayed
/// barcode reads slowly, and it costs nothing to avoid.
///
/// Colours are fixed black-on-white regardless of appearance: scanner contrast
/// is not something to theme.
struct BarcodeView: View {
    let symbol: Code128.Symbol
    var height: CGFloat = 180

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            context.withCGContext { cgContext in
                cgContext.setShouldAntialias(false)
                cgContext.interpolationQuality = .none

                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.fill(CGRect(origin: .zero, size: size))

                let moduleCount = CGFloat(symbol.moduleCount)
                guard moduleCount > 0 else { return }
                let moduleWidth = size.width / moduleCount

                cgContext.setFillColor(UIColor.black.cgColor)

                // Coalesce adjacent bar modules into single rects so the
                // rasteriser sees whole bars rather than abutting slices.
                var index = 0
                let modules = symbol.modules
                while index < modules.count {
                    guard modules[index] else {
                        index += 1
                        continue
                    }
                    var run = 1
                    while index + run < modules.count, modules[index + run] {
                        run += 1
                    }
                    let rect = CGRect(
                        x: CGFloat(index) * moduleWidth,
                        y: 0,
                        width: CGFloat(run) * moduleWidth,
                        height: size.height
                    )
                    cgContext.fill(rect)
                    index += run
                }
            }
        }
        .frame(height: height)
        .background(Palette.barcodePaper)
        .accessibilityHidden(true)
    }
}

/// A barcode with its SKU printed beneath, as it appears in scan mode.
struct BarcodePanel: View {
    let sku: String
    var height: CGFloat = 180
    var showsSKU: Bool = true

    private var symbol: Code128.Symbol? {
        try? Code128.encode(sku)
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            if let symbol {
                BarcodeView(symbol: symbol, height: height)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.s)
                    .background(Palette.barcodePaper)

                if showsSKU {
                    Text(sku)
                        .font(TypeScale.scanSKU)
                        .foregroundStyle(.black)
                        .tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel("SKU \(Format.spokenSKU(sku))")
                }
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "barcode")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Palette.textPlaceholder)
                    Text("This SKU cannot be encoded")
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textTertiary)
                    Text(sku)
                        .font(TypeScale.mono)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Palette.surface)
            }
        }
    }
}
