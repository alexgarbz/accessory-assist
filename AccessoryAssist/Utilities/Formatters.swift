import Foundation

/// Formatting shared across every screen, so a price or a timestamp never
/// renders two different ways in two different places.
enum Format {

    // MARK: - Money

    /// Prices are published in the catalogue's currency and are rendered in
    /// that currency's own convention — `$235.00`, not `USD 235.00`.
    ///
    /// The device locale is deliberately not used here: a phone set to another
    /// region would otherwise render the price in a form that does not match
    /// the mPOS terminal or the price tag on the shelf.
    private static let currencyLocale = Locale(identifier: "en_US")

    static func price(_ amount: Decimal, currency: String = "USD") -> String {
        amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(2))
                .locale(currencyLocale)
        )
    }

    /// Price without trailing zeros, for dense rows where `$235` reads faster
    /// than `$235.00`.
    static func compactPrice(_ amount: Decimal, currency: String = "USD") -> String {
        let isWhole = amount == amount.rounded(scale: 0)
        return amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(isWhole ? 0 : 2))
                .locale(currencyLocale)
        )
    }

    // MARK: - Timestamps

    /// Absolute, unambiguous timestamp — used for "Last updated" where staff may
    /// need to quote it to a manager.
    static func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Relative timestamp for at-a-glance status, e.g. "4 minutes ago".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "Last updated" line combining both forms.
    static func lastUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        return "\(timestamp(date)) · \(relative(date, now: now))"
    }

    // MARK: - Accessibility

    /// Spell a SKU out character by character so VoiceOver reads
    /// "T S L dash M Y…" rather than attempting to pronounce it as a word.
    static func spokenSKU(_ sku: String) -> String {
        sku.map { character in
            character == "-" ? "dash" : String(character)
        }
        .joined(separator: " ")
    }
}

extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}
