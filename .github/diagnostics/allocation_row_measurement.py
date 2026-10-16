"""Compare retained/fresh Form row measurement; diagnostic only, never ship."""
from pathlib import Path
import subprocess
import sys

part = sys.argv[1]
assert part in ('existing-copy-natural', 'fresh-copy-fixed', 'fresh-copy-natural', 'original-natural')
path = Path('CardPilot/Features/Transactions/TransactionsView.swift')


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


if part != 'original-natural':
    subprocess.run([
        sys.executable,
        str(Path(__file__).with_name('allocation_promotion_scope.py')),
        'copy',
    ], check=True)

source = path.read_text()
start = source.index('    private var promotionSection: some View {')
end = source.index('    private func promotionSummary(', start)
section = source[start:end]
marker = '.fixedSize(horizontal: false, vertical: true)'
assert section.count(marker) == 7
if part == 'original-natural':
    # The complete production screen, original UI test and original audit.
    # Remove only the seven explicit vertical-size overrides in this section.
    lines = section.splitlines(keepends=True)
    section = ''.join(line for line in lines if line.strip() != marker)
elif part.endswith('-natural'):
    # Keep original sizing for all prechecks; change only after diagnostic tap.
    section = section.replace(marker, '.fixedSize(horizontal: false, vertical: !diagnosticReduced)')
source = source[:start] + section + source[end:]

if part.startswith('fresh-'):
    source = once(source, '                    if !diagnosticReduced || diagnosticFormPart == "summary" || diagnosticFormPart == "promotions" {\n', '                    if !diagnosticReduced {\n')
    marker = '                    .accessibilityIdentifier("transaction.form")\n                    }\n'
    source = once(source, marker, marker + '''                    if diagnosticReduced {
                        Form {
                            promotionSection
                        }
                        .accessibilityIdentifier("allocation.diagnostic.fresh.copy")
                    }
''')

path.write_text(source)
if part != 'original-natural':
    ui = Path('CardPilotUITests/CoreFlowsUITests.swift')
    source = ui.read_text()
    source = once(source, 'captureScreenshot("促销审计范围-copy")', f'captureScreenshot("表单行度量-{part}")')
    ui.write_text(source)
