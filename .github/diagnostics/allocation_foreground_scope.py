"""Isolate foreground regions after original checks; diagnostic only, never ship."""
from pathlib import Path
import sys

scope = sys.argv[1]
assert scope in ('form', 'chrome', 'empty')


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
marker = '    @State private var editorStep = 0\n'
source = once(source, marker, marker + f'    @State private var diagnosticReduced = false\n    private let diagnosticAuditScope = "{scope}"\n')
marker = '                    if needsPromotionConfirmation || editorStep == 1 { editorStepIndicator }\n'
source = once(source, marker, '                    if !diagnosticReduced || diagnosticAuditScope == "chrome" {\n' + marker + '                    }\n')
marker = '                    Form {\n                        if editorStep == 0 {\n'
source = once(source, marker, '                    if !diagnosticReduced || diagnosticAuditScope == "form" {\n' + marker)
marker = '                    .accessibilityIdentifier("transaction.form")\n'
source = once(source, marker, marker + '                    }\n')
marker = '                    VStack(spacing: 0) {\n                        Divider()\n'
source = once(source, marker, '                    if !diagnosticReduced || diagnosticAuditScope == "chrome" {\n' + marker)
marker = '                    .background(.bar, ignoresSafeAreaEdges: .bottom)\n'
source = once(source, marker, marker + '''                    }
                    if diagnosticReduced && diagnosticAuditScope == "empty" {
                        Text("诊断静态页面")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
''')
start = source.index('struct TransactionEditorForm: View {')
toolbar = source.index('                .toolbar {\n', start)
marker = '                .toolbar {\n'
source = source[:toolbar] + source[toolbar:].replace(marker, marker + '''                    if !diagnosticReduced {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("开始诊断") {
                                focusedInput = nil
                                diagnosticReduced = true
                            }
                            .accessibilityIdentifier("allocation.diagnostic.reduce")
                        }
                    }
''', 1)
path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
marker = '        let beforeAudit = XCTAttachment(string: app.debugDescription)\n'
insertion = f'''        let reduce = app.buttons["allocation.diagnostic.reduce"]
        XCTAssertTrue(reduce.waitForExistence(timeout: 10))
        reduce.tap()
        XCTAssertTrue(reduce.waitForNonExistence(timeout: 10))
        captureScreenshot("前景审计范围-{scope}")
'''
source = once(source, marker, insertion + marker)
path.write_text(source)
