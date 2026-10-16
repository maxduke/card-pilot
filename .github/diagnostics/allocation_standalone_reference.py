"""Launch a stock Form reference from startup, without transaction interactions."""
from pathlib import Path
import sys

scope = sys.argv[1]
assert scope in ('root-one', 'root-many', 'sheet-many', 'sheet-clipped')


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/App/CardPilotApp.swift')
source = path.read_text()
marker = '        WindowGroup {\n            Group {\n'
source = once(source, marker, '''        WindowGroup {
            if let reference = ProcessInfo.processInfo.environment["CARDPILOT_ALLOCATION_REFERENCE"] {
                AllocationAuditReference(scope: reference)
            } else {
            Group {
''')
marker = '                Text("已启用备份数据，页面与提醒将重新计算。原存储文件仍保留。")\n            }\n'
source = once(source, marker, marker + '            }\n')
source += '\n' + Path(__file__).with_name('AllocationAuditReference.swift').read_text()
path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
method = f'''    func testAllocationReferenceClippingAudit() throws {{
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["CARDPILOT_UI_SCENARIO"] = "allocationFeedback"
        app.launchEnvironment["CARDPILOT_ALLOCATION_REFERENCE"] = "{scope}"
        app.launch()
        if "{scope}".hasPrefix("sheet-") {{
            let open = app.buttons["allocation.reference.open"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            open.tap()
        }}
        XCTAssertTrue(app.collectionViews["allocation.reference.form"].waitForExistence(timeout: 10))
        let content = app.staticTexts["allocation.reference.{'clipped' if scope == 'sheet-clipped' else 'text.0'}"]
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        captureScreenshot("独立审计对照-{scope}")
        let before = XCTAttachment(string: app.debugDescription)
        before.name = "独立对照审计前层级"
        before.lifetime = .keepAlways
        add(before)
        try app.performAccessibilityAudit(for: [.textClipped]) {{ issue in
            let details = "\\(issue.compactDescription)\\n\\(issue.detailedDescription)\\n\\(issue.element?.debugDescription ?? "No associated element")"
            let attachment = XCTAttachment(string: details)
            attachment.name = "独立对照完整审计元素"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            let screenshot = XCTAttachment(screenshot: self.app.screenshot())
            screenshot.name = "独立对照审计回调画面"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
            let hierarchy = XCTAttachment(string: self.app.debugDescription)
            hierarchy.name = "独立对照审计回调层级"
            hierarchy.lifetime = .keepAlways
            self.add(hierarchy)
            return false
        }}
    }}

'''
marker = '    func testCreateCardAndReopenDetails() {\n'
source = once(source, marker, method + marker)
path.write_text(source)
