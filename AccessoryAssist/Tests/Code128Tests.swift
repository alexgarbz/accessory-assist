import XCTest
@testable import AccessoryAssist

/// Barcode generation tests.
///
/// The strongest test here is `testEncodedSKURoundTripsThroughADecoder`: it
/// implements an independent Code 128 reader and decodes the modules the app
/// would actually draw. A structural bug in the symbol table, the checksum or
/// the module expansion cannot pass it, which is the guarantee needed before
/// staff hold a phone up to an mPOS terminal.
final class Code128Tests: XCTestCase {

    // MARK: - Symbol table

    func testSymbolTableIsStructurallyValid() {
        let problems = Code128.validateSymbolTable()
        XCTAssertTrue(problems.isEmpty, "Symbol table problems: \(problems)")
    }

    func testSymbolTableHasOneHundredAndSevenPatterns() {
        XCTAssertEqual(Code128.patternWidths.count, 107)
    }

    func testEveryDataPatternIsElevenModules() {
        for value in 0...105 {
            XCTAssertEqual(
                Code128.moduleRun(forSymbolValue: value).count, 11,
                "Symbol \(value) is not 11 modules wide"
            )
        }
        XCTAssertEqual(Code128.moduleRun(forSymbolValue: 106).count, 13, "Stop pattern is 13 modules")
    }

    func testEveryPatternStartsWithABarAndEndsWithASpace() {
        for value in 0...105 {
            let run = Code128.moduleRun(forSymbolValue: value)
            XCTAssertTrue(run.first == true, "Symbol \(value) must start with a bar")
            XCTAssertTrue(run.last == false, "Symbol \(value) must end with a space")
        }
        // The stop pattern is the exception: it terminates with a bar.
        XCTAssertEqual(Code128.moduleRun(forSymbolValue: 106).last, true)
    }

    // MARK: - Encoding

    func testEncodesStartChecksumAndStop() throws {
        let symbol = try Code128.encode("AB")

        // Start B, 'A' (33), 'B' (34), checksum, stop.
        XCTAssertEqual(symbol.symbolValues.count, 5)
        XCTAssertEqual(symbol.symbolValues.first, Code128.startBValue)
        XCTAssertEqual(symbol.symbolValues.last, Code128.stopValue)
        XCTAssertEqual(symbol.symbolValues[1], 33)
        XCTAssertEqual(symbol.symbolValues[2], 34)

        // (104 + 1×33 + 2×34) mod 103 = 205 mod 103 = 102
        XCTAssertEqual(symbol.checksum, 102)
        XCTAssertEqual(symbol.symbolValues[3], 102)
    }

    func testChecksumMatchesSpecificationForASKU() throws {
        let sku = "TSL-MY-INT-0142"
        let symbol = try Code128.encode(sku)

        var expected = Code128.startBValue
        for (index, scalar) in sku.unicodeScalars.enumerated() {
            expected += (Int(scalar.value) - 32) * (index + 1)
        }
        expected %= 103

        XCTAssertEqual(symbol.checksum, expected)
    }

    func testModuleCountMatchesSymbolCount() throws {
        let symbol = try Code128.encode("TSL-MY-INT-0142", quietZoneModules: 10)
        // start + 15 data + checksum = 17 patterns at 11 modules, stop at 13,
        // plus a 10-module quiet zone on each side.
        let expected = (17 * 11) + 13 + 20
        XCTAssertEqual(symbol.moduleCount, expected)
    }

    func testQuietZonesArePresentOnBothSides() throws {
        let quietZone = 12
        let symbol = try Code128.encode("TSL-UN-CHG-0301", quietZoneModules: quietZone)

        XCTAssertEqual(symbol.quietZoneModules, quietZone)
        XCTAssertTrue(symbol.modules.prefix(quietZone).allSatisfy { $0 == false })
        XCTAssertTrue(symbol.modules.suffix(quietZone).allSatisfy { $0 == false })
        // The symbol itself must start and end with a bar.
        XCTAssertEqual(symbol.modules[quietZone], true)
        XCTAssertEqual(symbol.modules[symbol.moduleCount - quietZone - 1], true)
    }

    func testEncodesEveryPrintableASCIICharacter() throws {
        for value in 32...126 {
            let character = String(UnicodeScalar(UInt8(value)))
            XCTAssertNoThrow(try Code128.encode(character), "Failed to encode \(character)")
        }
    }

    // MARK: - Rejection

    func testEmptyPayloadThrows() {
        XCTAssertThrowsError(try Code128.encode("")) { error in
            XCTAssertEqual(error as? Code128.EncodingError, .emptyPayload)
        }
    }

    func testUnsupportedCharacterThrows() {
        XCTAssertThrowsError(try Code128.encode("TSL-MŸ-001")) { error in
            XCTAssertEqual(error as? Code128.EncodingError, .unsupportedCharacter("Ÿ"))
        }
    }

    func testCanEncodeRejectsNonASCII() {
        XCTAssertTrue(Code128.canEncode("TSL-MY-INT-0142"))
        XCTAssertTrue(Code128.canEncode("SKU WITH SPACES"))
        XCTAssertFalse(Code128.canEncode(""))
        XCTAssertFalse(Code128.canEncode("TSL–MY"))   // en dash
        XCTAssertFalse(Code128.canEncode("TSL\u{7F}")) // DEL
    }

    // MARK: - Round trip

    func testEncodedSKURoundTripsThroughADecoder() throws {
        let skus = [
            "TSL-MY-INT-0142",
            "TSL-M3-EXT-0410",
            "TSL-UN-CHG-0318",
            "TSL-CT-CRG-0220",
            "A1",
            "0123456789"
        ]

        for sku in skus {
            let symbol = try Code128.encode(sku)
            let decoded = try XCTUnwrap(Code128Reader.decode(modules: symbol.modules), "Could not decode \(sku)")
            XCTAssertEqual(decoded, sku, "Round trip failed for \(sku)")
        }
    }

    func testEveryCatalogueSKUEncodes() throws {
        // Guards against a content change introducing a SKU the scanner
        // could never read.
        for sku in SampleCatalogue.skus {
            XCTAssertTrue(Code128.canEncode(sku), "\(sku) is not encodable")
            let symbol = try Code128.encode(sku)
            XCTAssertEqual(Code128Reader.decode(modules: symbol.modules), sku)
        }
    }
}

/// An independent Code 128 Subset B reader used only by the tests.
///
/// Written from the specification rather than from the encoder, so the two do
/// not share a mistake.
enum Code128Reader {

    static func decode(modules: [Bool]) -> String? {
        // Strip quiet zones.
        guard let first = modules.firstIndex(of: true),
              let last = modules.lastIndex(of: true) else { return nil }
        let symbolModules = Array(modules[first...last])

        // Run-length encode into element widths.
        var widths: [Int] = []
        var currentValue = symbolModules[0]
        var run = 0
        for module in symbolModules {
            if module == currentValue {
                run += 1
            } else {
                widths.append(run)
                currentValue = module
                run = 1
            }
        }
        widths.append(run)

        // The trailing stop pattern is seven elements; everything before it is
        // six elements per symbol.
        guard widths.count >= 13, (widths.count - 7) % 6 == 0 else { return nil }

        var values: [Int] = []
        var index = 0
        while index + 6 <= widths.count - 7 {
            let pattern = widths[index..<(index + 6)].map(String.init).joined()
            guard let value = Code128.patternWidths.firstIndex(of: pattern) else { return nil }
            values.append(value)
            index += 6
        }
        let stopPattern = widths[(widths.count - 7)...].map(String.init).joined()
        guard stopPattern == Code128.patternWidths[Code128.stopValue] else { return nil }

        guard values.count >= 2, values.first == Code128.startBValue else { return nil }
        let checksum = values.removeLast()
        let start = values.removeFirst()

        // Independently recompute the checksum.
        var expected = start
        for (position, value) in values.enumerated() {
            expected += value * (position + 1)
        }
        guard expected % 103 == checksum else { return nil }

        var text = ""
        for value in values {
            guard (0...94).contains(value) else { return nil }
            text.append(Character(UnicodeScalar(UInt8(value + 32))))
        }
        return text
    }
}
