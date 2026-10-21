import os
from pathlib import Path

variant = os.environ['AUDIT_VARIANT']
sections = {'control': 'all', 'title_only': 'header', 'wheel_only': 'quick', 'title_frame': 'schedule', 'title_padding': 'promotion', 'no_fixed': 'info'}
assert variant in sections

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

path = Path('CardPilot/Features/Cards/CardDetailsView.swift')
source = path.read_text()
keep = sections[variant]
if keep != 'all':
    markers = {'quick': '            Section("快捷操作") {', 'schedule': '            Section("账单日程") {', 'promotion': '            Section("适用活动") {', 'info': '            Section("卡片信息") {'}
    for key, marker in markers.items():
        if keep != key:
            start, _, end = block(source, marker)
            source = source[:start] + source[end:]
    if keep != 'header':
        start, _, end = block(source, '            Section {')
        source = source[:start] + source[end:]
path.write_text(source)

path = Path('CardPilot/Features/Shared/Formatting.swift')
source = path.read_text()
start = source.index('struct BillingDatePicker: View {')
end = source.index('struct CurrencyPickerView: View {', start)
picker = source[start:end]
anchor = '                    .accessibilityIdentifier("\\(identifier).label")'
assert picker.count(anchor) == 1
if variant == 'title_only':
    wheel = '                picker\n                    .labelsHidden()\n                    .datePickerStyle(.wheel)'
    assert picker.count(wheel) == 1
    picker = picker.replace(wheel, '                Color.clear.frame(height: 216)', 1)
elif variant == 'wheel_only':
    picker = picker.replace(anchor, anchor + '\n                    .hidden()', 1)
elif variant == 'title_frame':
    picker = picker.replace(anchor, '                    .frame(maxWidth: .infinity, alignment: .leading)\n' + anchor, 1)
elif variant == 'title_padding':
    picker = picker.replace(anchor, '                    .padding(.vertical, 4)\n' + anchor, 1)
elif variant == 'no_fixed':
    picker = picker.replace('                    .fixedSize(horizontal: false, vertical: true)\n', '', 1)
source = source[:start] + picker + source[end:]
path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
methods = '''
    func testNativeScheduleClippingIsolation() throws {
        launch("core")
        openCard("UI Primary")
        XCTAssertTrue(app.navigationBars["卡片详情"].waitForExistence(timeout: 10))
        if "VARIANT" == "control" {
            let bank = app.staticTexts["银行、UI Test Bank"]
            reveal(bank, fullyVisible: true, navigationBar: app.navigationBars["卡片详情"])
        }
        captureAccessibilityAuditContext("分组日程VARIANT审计前")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true)
    }

    func testNativeDateClippingIsolation() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        launch("billingDateFeedback")
        openBillingFeedbackAccount()
        openBillingFeedbackCycle(offset: 0)
        tap(app.buttons["调整本期日期"])
        let nav = app.navigationBars["调整本期日期"]
        XCTAssertTrue(nav.waitForExistence(timeout: 10))
        setBillingDateToggle("billingDates.statement.enabled", enabled: false)
        let form = app.collectionViews["billingDates.form"]
        reveal(app.staticTexts["billingDates.explanation"], fullyVisible: true,
               navigationBar: nav, contentContainer: form)
        captureAccessibilityAuditContext("标题日期VARIANT审计前")
        try auditAccessibility(for: [.textClipped], captureFailureContext: true)
    }
'''.replace('VARIANT', variant)
anchor = '    func testAccountBillingDateWheelsAtLargestTextSizeSaveAndPreserveRepayment() throws {'
assert source.count(anchor) == 1
path.write_text(source.replace(anchor, methods + '\n' + anchor, 1))
print('Applied title/date and card-section diagnostic:', variant, keep)
