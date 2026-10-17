"""Compare scalable input reservation with the exact current input layout."""
from pathlib import Path
import ast
import subprocess
import sys

scope = sys.argv[1]
assert scope in ('baseline', 'scaled-inputs')


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
if scope == 'scaled-inputs':
    marker = '    @ScaledMetric(relativeTo: .caption) private var stepIndicatorSize = 28\n'
    source = once(source, marker, marker + '''    // Keep one body line available while native input fonts change size.
    @ScaledMetric(relativeTo: .body) private var promotionInputLineHeight = 22
''')
    marker = '            TextField("搜索其他促销", text: $promotionSearchText)\n'
    source = once(source, marker, marker + '''                .font(.body)
                .frame(minHeight: max(44, promotionInputLineHeight))
''')
    marker = r'''                            .textFieldStyle(.plain)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(promotion.title)计入金额（\(promotion.progressCurrencyCode)）")'''
    replacement = r'''                            .textFieldStyle(.plain)
                            .font(.body)
                            .frame(minHeight: max(44, promotionInputLineHeight))
                            .accessibilityLabel("\(promotion.title)计入金额（\(promotion.progressCurrencyCode)）")'''
    source = once(source, marker, replacement)
    path.write_text(source)

# Require a usable field target as well as the existing dismissal-button target.
tests = Path('CardPilotUITests/CoreFlowsUITests.swift')
ui = tests.read_text()
for title in ['促销计入金额键盘收起入口', '最大字号促销计入金额键盘收起入口']:
    marker = f'        captureScreenshot("{title}")\n'
    ui = once(ui, marker, '        assertTouchTarget(allocation)\n' + marker)
tests.write_text(ui)

# Freeze only the proposed public application/test repair, before observation.
patch = subprocess.check_output(['git', 'diff', '--binary'])
Path('../repair.patch').write_bytes(patch)
subprocess.run([
    sys.executable,
    str(Path(__file__).with_name('allocation_issue_metadata.py')),
    'actual',
], check=True)

# Reuse only the previously compiled passive UIKit observer. Do not apply the
# older script's font replacement or change any native font/frame properties.
old = ast.parse(Path(__file__).with_name('allocation_native_metrics.py').read_text())
observers = [
    node.value.value for node in old.body
    if isinstance(node, ast.AugAssign)
    and isinstance(node.target, ast.Name) and node.target.id == 'source'
    and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)
    and 'private struct AllocationNativeAuditProbe' in node.value.value
]
assert len(observers) == 1
source = path.read_text()
source = once(source, 'import SwiftUI\n', 'import SwiftUI\nimport UIKit\n')
marker = '                    .accessibilityIdentifier("transaction.form")\n'
source = once(source, marker, marker + r'''                    .background(AllocationNativeAuditProbe(state: "\(dynamicTypeSize)|step=\(editorStep)|errors=\(showingAllocationErrors)"))
''' )
source += observers[0]
path.write_text(source)
