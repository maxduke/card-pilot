"""Audit separate real screens to locate the unattributed report; never ship."""
from pathlib import Path
import sys

stage = sys.argv[1]
assert stage in ('detail_only', 'valid_form', 'invalid_form')
path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
marker = '    func testAllocationErrorLocationAndCompletePromptAtLargestTextSize() throws {'
start = source.index(marker)
end = source.index('    func testTransactionAllocationPersistsAndUpdatesPromotion()', start)
case = source[start:end]
capture = '        captureScreenshot("最大字号计入金额错误定位")'
assert case.count(capture) == 1
if stage == 'detail_only':
    before_editor = case.index('        tap(app.buttons["card.addTransaction"])')
    case = case[:before_editor] + case[case.index(capture):]
    case = case.replace(capture, '        captureScreenshot("最大字号卡片详情文字诊断")', 1)
elif stage == 'valid_form':
    correction = '''        first.tap()
        first.typeText(XCUIKeyboardKey.delete.rawValue + "125.5")
        XCTAssertEqual(first.value as? String, "125.5")
        XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
        dismissal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(error.exists)
'''
    case = case.replace(capture, correction + '        captureScreenshot("最大字号有效计入金额文字诊断")', 1)
path.write_text(source[:start] + case + source[end:])
