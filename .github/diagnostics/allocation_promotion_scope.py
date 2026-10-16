"""Isolate promotion row kinds after all original checks; diagnostic only."""
from pathlib import Path
import subprocess
import sys

part = sys.argv[1]
assert part in ('search', 'toggles', 'amounts', 'copy')
subprocess.run([
    sys.executable,
    str(Path(__file__).with_name('allocation_form_scope.py')),
    'promotions',
], check=True)


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
marker = '    private let diagnosticFormPart = "promotions"\n'
source = once(source, marker, marker + f'    private let diagnosticPromotionPart = "{part}"\n')
start = source.index('    private var promotionSection: some View {')
end = source.index('    private func promotionSummary(', start)
section = source[start:end]
marker = '            TextField("搜索其他促销", text: $promotionSearchText)\n'
section = once(section, marker, '''            if !diagnosticReduced || diagnosticPromotionPart == "search" {
''' + marker + '            }\n')
marker = '                    Toggle(isOn: promotionBinding(promotion.id)) {\n'
section = once(section, marker, '''                    if !diagnosticReduced || diagnosticPromotionPart == "toggles" {
''' + marker)
marker = '                    if dynamicTypeSize.isAccessibilitySize {\n'
section = once(section, marker, '''                    }
                    if (!diagnosticReduced || diagnosticPromotionPart == "copy") && dynamicTypeSize.isAccessibilitySize {
''')
marker = '                    if selectedPromotionIDs.contains(promotion.id) {\n'
section = once(section, marker, '''                    if (!diagnosticReduced || diagnosticPromotionPart == "amounts") && selectedPromotionIDs.contains(promotion.id) {
''')
marker = '                    if postingDatePendingPromotions.contains(where: { $0.id == promotion.id }) {\n'
section = once(section, marker, '''                    if (!diagnosticReduced || diagnosticPromotionPart == "copy") && postingDatePendingPromotions.contains(where: { $0.id == promotion.id }) {
''')
marker = '                Text("已报名或无需报名、金额符合条件的累计活动会预选。不可叠加的多个活动及逐笔优惠活动，请逐项确认。")\n'
section = once(section, marker, '''                if !diagnosticReduced || diagnosticPromotionPart == "copy" {
''' + marker)
marker = '''                if selectedPromotionIDs.contains(where: { id in
                    promotions.first(where: { $0.id == id })?.enrollmentStatus == .notEnrolled
                }) {
                    Text("所选活动中有尚未报名的活动，请确认报名状态。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
'''
section = once(section, marker, marker + '                }\n')
source = source[:start] + section + source[end:]
path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
source = once(source, 'captureScreenshot("表单审计范围-promotions")', f'captureScreenshot("促销审计范围-{part}")')
path.write_text(source)
