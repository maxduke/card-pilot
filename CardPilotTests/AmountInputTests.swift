import XCTest
@testable import CardPilot

final class AmountInputTests: XCTestCase {
    func testCommaDecimalIsNeverTreatedAsThousands() {
        for identifier in ["de_DE", "fr_FR", "pt_BR"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(AmountInput.decimal("12,50", locale: locale), 12.5)
            XCTAssertEqual(AmountInput.decimal("1,500", locale: locale), 1.5)
            XCTAssertEqual(AmountInput.decimal(",5", locale: locale), 0.5)
            XCTAssertNil(AmountInput.decimal("1,500,000", locale: locale))
        }
    }

    func testGroupingAndDecimalSeparatorsMustMatchLocale() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(AmountInput.decimal("1.234,50", locale: german), 1_234.5)
        XCTAssertNil(AmountInput.decimal("12.34,50", locale: german))
        XCTAssertNil(AmountInput.decimal("1,234.50", locale: german))
        let chinese = Locale(identifier: "zh_CN")
        XCTAssertEqual(AmountInput.decimal("1,234.50", locale: chinese), 1_234.5)
        XCTAssertNil(AmountInput.decimal("12,34.50", locale: chinese))
        XCTAssertNil(AmountInput.decimal("1.234,50", locale: chinese))
    }

    func testFrenchGroupingUsesTheLocaleSpaceSeparator() throws {
        let locale = Locale(identifier: "fr_FR")
        let grouping = try XCTUnwrap(locale.groupingSeparator)
        XCTAssertEqual(AmountInput.decimal("1\(grouping)234,50", locale: locale), 1_234.5)
        XCTAssertNil(AmountInput.decimal("12\(grouping)34,50", locale: locale))
    }

    func testRegionalGroupingRoundTripsTheSystemFormatter() throws {
        for identifier in ["en_IN", "hi_IN", "en_US", "fr_FR", "ar_EG"] {
            let locale = Locale(identifier: identifier)
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            let text = try XCTUnwrap(formatter.string(from: 123_456.75))
            XCTAssertEqual(AmountInput.decimal(text, locale: locale), 123_456.75, identifier)
        }
    }

    func testEditableValuesPreservePrecisionAcrossLocales() {
        let amount = Decimal(string: "1234.00500000000000001")!
        for identifier in ["zh_CN", "en_US", "de_DE", "fr_FR", "ar_EG", "en_IN"] {
            let locale = Locale(identifier: identifier)
            let text = AmountInput.text(amount, locale: locale)
            XCTAssertEqual(AmountInput.decimal(text, locale: locale), amount, identifier)
        }
        XCTAssertEqual(AmountInput.text(Decimal(string: "1.005")!, locale: Locale(identifier: "de_DE")), "1,005")
    }

    func testTrailingSeparatorDoesNotInvalidateAnAmountWhileTyping() {
        XCTAssertEqual(AmountInput.decimal("12.", locale: Locale(identifier: "en_US")), 12)
        XCTAssertEqual(AmountInput.decimal("12,", locale: Locale(identifier: "de_DE")), 12)
        XCTAssertNil(AmountInput.decimal(",", locale: Locale(identifier: "de_DE")))
    }

    func testDecimalDigitsCanBeEnteredWithNonAsciiKeyboards() {
        XCTAssertEqual(AmountInput.decimal("１２３４.５０", locale: Locale(identifier: "zh_CN")), 1_234.5)
        XCTAssertEqual(AmountInput.decimal("١٢٣٤٫٥٠", locale: Locale(identifier: "ar_EG")), 1_234.5)
        XCTAssertNil(AmountInput.decimal("½", locale: Locale(identifier: "en_US")))
    }

    func testMalformedAndNonFiniteValuesAreRejected() {
        let locale = Locale(identifier: "en_US")
        for text in ["", ".", "+", "12abc", "1.2.3", "1e", "NaN", "Infinity", "1e1000", "1\n2"] {
            XCTAssertNil(AmountInput.decimal(text, locale: locale), text)
        }
        XCTAssertEqual(AmountInput.decimal(" +.5e1 ", locale: locale), 5)
    }
}
