import XCTest
@testable import CardPilot

final class FormattingTests: XCTestCase {
    func testDecimalParsesDisplayedChineseGroupingAndOrdinaryDecimals() {
        XCTAssertEqual(CardPilotUI.decimal(CardPilotUI.amountText(8_000)), 8_000)
        XCTAssertEqual(CardPilotUI.decimal("8000.50"), 8_000.5)
        XCTAssertEqual(CardPilotUI.decimal("+.5e1"), 5)
    }

    func testEditableAmountTextRoundTripsExactDecimal() {
        let amount = Decimal(string: "1.005")!
        XCTAssertEqual(CardPilotUI.editableAmountText(amount), "1.005")
        XCTAssertEqual(CardPilotUI.decimal(CardPilotUI.editableAmountText(amount)), amount)
    }

    func testDecimalRejectsPartialOrMalformedNumbers() {
        for value in ["12abc", "1.2.3", "12,34", "", ".", "+", "1e", "1,000.2.3"] {
            XCTAssertNil(CardPilotUI.decimal(value), "应拒绝：\(value)")
        }
    }

    func testReminderTimeRequiresExactlyTwoAsciiDigitsPerComponent() {
        XCTAssertEqual(CardPilotUI.parseReminderTime("09:30"), .init(hour: 9, minute: 30))
        for value in ["9:30", "09:3", "09:x:30", "09:30:00", "09:300", "090:30", "24:00", "09:60"] {
            XCTAssertNil(CardPilotUI.parseReminderTime(value), "应拒绝：\(value)")
        }
    }
}
