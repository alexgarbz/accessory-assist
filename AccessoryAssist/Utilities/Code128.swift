import Foundation

/// Code 128 (Subset B) symbol generation.
///
/// Code 128 is used rather than a numeric-only symbology because SKUs in this
/// catalogue are alphanumeric with hyphens (`TSL-MY-INT-0142`). Subset B covers
/// the full printable ASCII range 32–126, so any SKU the content team can type
/// encodes without transformation, and every mPOS scanner in the field reads
/// Code 128 by default.
///
/// This type is deliberately free of UIKit and Core Image: it turns a string
/// into an array of modules (`true` = bar, `false` = space) and nothing else,
/// which is what makes it directly testable and resolution-independent when
/// drawn. Barcode images are never stored — they are generated from the SKU on
/// device, every time.
enum Code128 {

    // MARK: - Errors

    enum EncodingError: Error, Equatable, LocalizedError {
        case emptyPayload
        case unsupportedCharacter(Character)

        var errorDescription: String? {
            switch self {
            case .emptyPayload:
                return "Cannot generate a barcode from an empty SKU."
            case .unsupportedCharacter(let character):
                return "The character \"\(character)\" cannot be encoded in Code 128 Subset B."
            }
        }
    }

    // MARK: - Symbol table

    /// Element widths for symbol values 0–106. Each string is six alternating
    /// bar/space widths (bar first) totalling 11 modules; value 106 (Stop) is
    /// seven elements totalling 13 modules.
    static let patternWidths: [String] = [
        "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312",
        "132212", "221213", "221312", "231212", "112232", "122132", "122231", "113222",
        "123122", "123221", "223211", "221132", "221231", "213212", "223112", "312131",
        "311222", "321122", "321221", "312212", "322112", "322211", "212123", "212321",
        "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
        "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121",
        "313121", "211331", "231131", "213113", "213311", "213131", "311123", "311321",
        "331121", "312113", "312311", "332111", "314111", "221411", "431111", "111224",
        "111422", "121124", "121421", "141122", "141221", "112214", "112412", "122114",
        "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
        "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112",
        "421211", "212141", "214121", "412121", "111143", "111341", "131141", "114113",
        "114311", "411113", "411311", "113141", "114131", "311141", "411131", "211412",
        "211214", "211232", "2331112"
    ]

    /// Symbol value that starts a Subset B sequence.
    static let startBValue = 104
    /// Symbol value that terminates every sequence.
    static let stopValue = 106
    /// Checksum modulus defined by the specification.
    static let checksumModulus = 103

    /// Default quiet zone. The specification requires at least 10 modules of
    /// clear space either side; scanners are noticeably less tolerant without it.
    static let defaultQuietZoneModules = 12

    // MARK: - Encoding

    /// A finished symbol, ready to draw.
    struct Symbol: Equatable {
        /// The payload that was encoded.
        let value: String
        /// Symbol values including start, data, checksum and stop.
        let symbolValues: [Int]
        /// Modulo-103 checksum character value.
        let checksum: Int
        /// Bar/space modules including quiet zones. `true` is a bar.
        let modules: [Bool]
        /// Quiet zone width applied to each side, in modules.
        let quietZoneModules: Int

        var moduleCount: Int { modules.count }
    }

    /// True when every character can be represented in Subset B.
    static func canEncode(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { (32...126).contains($0.value) }
    }

    /// Encode a payload into a drawable symbol.
    ///
    /// - Parameters:
    ///   - text: the SKU, or any printable ASCII payload.
    ///   - quietZoneModules: clear modules added to each side.
    static func encode(
        _ text: String,
        quietZoneModules: Int = defaultQuietZoneModules
    ) throws -> Symbol {
        guard !text.isEmpty else { throw EncodingError.emptyPayload }

        var dataValues: [Int] = []
        dataValues.reserveCapacity(text.count)
        for character in text {
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1,
                  (32...126).contains(scalar.value) else {
                throw EncodingError.unsupportedCharacter(character)
            }
            dataValues.append(Int(scalar.value) - 32)
        }

        // Weighted modulo-103 checksum: start value, then each data value
        // multiplied by its one-based position.
        var checksum = startBValue
        for (index, value) in dataValues.enumerated() {
            checksum += value * (index + 1)
        }
        checksum %= checksumModulus

        let symbolValues = [startBValue] + dataValues + [checksum, stopValue]

        let quietZone = max(0, quietZoneModules)
        var modules: [Bool] = Array(repeating: false, count: quietZone)
        for value in symbolValues {
            modules.append(contentsOf: moduleRun(forSymbolValue: value))
        }
        modules.append(contentsOf: Array(repeating: false, count: quietZone))

        return Symbol(
            value: text,
            symbolValues: symbolValues,
            checksum: checksum,
            modules: modules,
            quietZoneModules: quietZone
        )
    }

    /// Expand one symbol value into its bar/space modules.
    static func moduleRun(forSymbolValue value: Int) -> [Bool] {
        guard patternWidths.indices.contains(value) else { return [] }
        var run: [Bool] = []
        var isBar = true
        for width in patternWidths[value] {
            let count = width.wholeNumberValue ?? 0
            run.append(contentsOf: Array(repeating: isBar, count: count))
            isBar.toggle()
        }
        return run
    }

    // MARK: - Self check

    /// Structural checks on the symbol table. Exercised by the unit tests so a
    /// mistyped pattern can never ship silently.
    static func validateSymbolTable() -> [String] {
        var problems: [String] = []
        guard patternWidths.count == 107 else {
            return ["Expected 107 patterns, found \(patternWidths.count)"]
        }
        for (value, pattern) in patternWidths.enumerated() {
            let widths = pattern.compactMap(\.wholeNumberValue)
            guard widths.count == pattern.count else {
                problems.append("Pattern \(value) contains a non-digit")
                continue
            }
            let expectedElements = value == stopValue ? 7 : 6
            let expectedModules = value == stopValue ? 13 : 11
            if widths.count != expectedElements {
                problems.append("Pattern \(value) has \(widths.count) elements, expected \(expectedElements)")
            }
            if widths.reduce(0, +) != expectedModules {
                problems.append("Pattern \(value) spans \(widths.reduce(0, +)) modules, expected \(expectedModules)")
            }
            if widths.contains(where: { $0 < 1 || $0 > 4 }) {
                problems.append("Pattern \(value) has an element outside 1–4 modules")
            }
        }
        if Set(patternWidths).count != patternWidths.count {
            problems.append("Symbol table contains duplicate patterns")
        }
        return problems
    }
}
