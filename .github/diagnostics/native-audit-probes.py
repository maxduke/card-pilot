import os
from pathlib import Path

variant = os.environ['AUDIT_VARIANT']
assert variant in ('control', 'single', 'reduced', 'bare')

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    for index in range(opening + 1, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return start, opening, index + 1
    raise AssertionError('Unbalanced source block')

card = Path('CardPilot/Features/Cards/CardDetailsView.swift')
source = card.read_text()
if variant in ('reduced', 'bare'):
    start, _, end = block(source, '            Section("快捷操作") {')
    source = source[:start] + source[end:]
    start, _, end = block(source, '            Section {')
    source = source[:start] + source[end:]
if variant == 'bare':
    _, opening, end = block(source, '        List {')
    source = source[:opening + 1] + '\n            Text("账单日程")\n        ' + source[end - 1:]
card.write_text(source)

if variant == 'bare':
    path = Path('CardPilot/Features/Cards/BillingCycleDetailView.swift')
    source = path.read_text()
    start = source.index('private struct BillingCycleDatesEditor: View {')
    _, opening, end = block(source[start:], '                Form {')
    opening += start
    end += start
    source = source[:opening + 1] + '\n                    Text("还款日")\n                ' + source[end - 1:]
    path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
methods = '''
    func testNativeScheduleClippingIsolation() throws {
        launch("core")
        openCard("UI Primary")
        let nav = app.navigationBars["卡片详情"]
        if "VARIANT" != "bare" {
            let bank = app.staticTexts["银行、UI Test Bank"]
            reveal(bank, fullyVisible: true, navigationBar: nav)
            if "VARIANT" == "single" {
                // Move the transaction title below the navigation bar. The
                // footer's glyphs still fit despite a partly visible cell.
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: app.frame.width * 0.03, dy: 400))
                let end = origin.withOffset(CGVector(dx: app.frame.width * 0.03, dy: 423))
                start.press(forDuration: 0.05, thenDragTo: end,
                            withVelocity: .slow, thenHoldForDuration: 0.2)
            }
        }
        captureAccessibilityAuditContext("隔离日程VARIANT审计前")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true)
    }

    func testNativeDateClippingIsolation() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("billingDateFeedback")
        openBillingFeedbackAccount()
        openBillingFeedbackCycle(offset: 0)
        tap(app.buttons["调整本期日期"])
        let nav = app.navigationBars["调整本期日期"]
        if "VARIANT" != "bare" {
            if "VARIANT" == "single" || "VARIANT" == "reduced" {
                setBillingDateToggle("billingDates.statement.enabled", enabled: false)
            }
            if "VARIANT" == "reduced" {
                setBillingDateToggle("billingDates.repayment.enabled", enabled: false)
            }
            let form = app.collectionViews["billingDates.form"]
            reveal(app.staticTexts["billingDates.explanation"], fullyVisible: true,
                   navigationBar: nav, contentContainer: form)
        }
        captureAccessibilityAuditContext("隔离日期VARIANT审计前")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true)
    }
'''.replace('VARIANT', variant)
anchor = '    func testAccountBillingDateWheelsAtLargestTextSizeSaveAndPreserveRepayment() throws {'
assert source.count(anchor) == 1
source = source.replace(anchor, methods + '\n' + anchor, 1)
path.write_text(source)
print('Applied isolated diagnostic variant:', variant)
