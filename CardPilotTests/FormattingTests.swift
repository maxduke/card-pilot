import XCTest
@testable import CardPilot

final class FormattingTests: XCTestCase {
    func testDecimalParsesDisplayedChineseGroupingAndOrdinaryDecimals() {
        XCTAssertEqual(CardPilotUI.decimal(CardPilotUI.amountText(8_000)), 8_000)
        XCTAssertEqual(CardPilotUI.decimal("8000.50"), 8_000.5)
    }
}
