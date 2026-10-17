"""Mask AX groups after original checks, preserving the complete visible Form."""
from pathlib import Path
import subprocess
import sys

scope = sys.argv[1]
assert scope in ('toggles', 'amounts', 'copy', 'none')
subprocess.run([
    sys.executable,
    str(Path(__file__).with_name('allocation_issue_metadata.py')),
    'actual',
], check=True)


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
marker = '    @State private var editorStep = 0\n'
source = once(source, marker, marker + f'''    @State private var diagnosticAuditMask = false
    private let diagnosticAuditScope = "{scope}"
''')
start = source.index('struct TransactionEditorForm: View {')
toolbar = source.index('                .toolbar {\n', start)
source = source[:toolbar] + source[toolbar:].replace('                .toolbar {\n', '''                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("诊断") { diagnosticAuditMask.toggle() }
                            .accessibilityIdentifier("allocation.diagnostic.mask")
                            .accessibilityValue(diagnosticAuditMask ? diagnosticAuditScope : "unmasked")
                    }
''', 1)
start = source.index('    private var promotionConfirmationSections: some View {')
end = source.index('    private func continueToPromotionConfirmation()', start)
section = source[start:end]
marker = '''            if !merchant.isEmpty { LabeledContent("商户", value: merchant) }
        }
'''
section = once(section, marker, marker + '        .accessibilityHidden(diagnosticAuditMask)\n')
marker = '''        } header: {
            Text("确认促销")
        }
'''
section = once(section, marker, marker + '        .accessibilityHidden(diagnosticAuditMask)\n')
source = source[:start] + section + source[end:]

start = source.index('    private var promotionSection: some View {')
end = source.index('    private func promotionSummary(', start)
section = source[start:end]
marker = '            TextField("搜索其他促销", text: $promotionSearchText)\n'
section = once(section, marker, marker + '                .accessibilityHidden(diagnosticAuditMask)\n')
marker = '                    .accessibilityIdentifier("allocation.toggle.\\(promotion.title)")\n'
section = once(section, marker, marker + '                    .accessibilityHidden(diagnosticAuditMask && diagnosticAuditScope != "toggles")\n')
marker = '''                        Text(promotionSummary(promotion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
'''
section = once(section, marker, marker + '                            .accessibilityHidden(diagnosticAuditMask && diagnosticAuditScope != "copy")\n')
marker = '                        .id(InputField.allocation(promotion.id))\n'
section = once(section, marker, marker + '                        .accessibilityHidden(diagnosticAuditMask && diagnosticAuditScope != "amounts")\n')
copy_lines = [
    'Text("当前卡片和日期没有匹配的活动；仍可搜索全部促销并手动选择。")',
    'Text("没有匹配的促销。可修改搜索词，或返回上一步检查卡片和日期。")',
    'Text(warning)',
    'Text("需补入账日期，不会自动勾选。")',
    'Text("已报名或无需报名、金额符合条件的累计活动会预选。不可叠加的多个活动及逐笔优惠活动，请逐项确认。")',
    'Text("已带入原消费已有的促销分配，即使活动已结束也会保留。")',
    'Text("所选活动中包含“不允许叠加”的活动，请按活动条款确认。")',
    'Text("所选活动当前不再符合卡片或日期候选条件，请确认后再保存。")',
    'Text("所选活动中有尚未报名的活动，请确认报名状态。")',
]
for line in copy_lines:
    section = once(section, line + '\n', line + '\n                        .accessibilityHidden(diagnosticAuditMask && diagnosticAuditScope != "copy")\n')
source = source[:start] + section + source[end:]
path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
marker = '        let beforeAudit = XCTAttachment(string: app.debugDescription)\n'
source = once(source, marker, f'''        let mask = app.buttons["allocation.diagnostic.mask"]
        XCTAssertTrue(mask.waitForExistence(timeout: 10))
        let originalHeaderFrame = progress.frame
        let originalSaveFrame = save.frame
        mask.tap()
        XCTAssertEqual(mask.value as? String, "{scope}")
        XCTAssertEqual(progress.frame, originalHeaderFrame)
        XCTAssertEqual(save.frame, originalSaveFrame)
        captureScreenshot("AX范围-{scope}-完整画面")
''' + marker)
marker = '        let promotionTitle = app.switches["allocation.toggle.\\(allocationFeedbackFirstTitle)"]\n'
source = once(source, marker, '        mask.tap()\n        XCTAssertEqual(mask.value as? String, "unmasked")\n' + marker)
path.write_text(source)
