import os
from pathlib import Path
variant = os.environ['AUDIT_VARIANT']
assert variant in ('caption', 'text')

path = Path('CardPilot/Features/Shared/Formatting.swift')
source = path.read_text()
anchor = '                    .accessibilityIdentifier("\\(identifier).label")'
assert source.count(anchor) == 1
path.write_text(source.replace(anchor, '                    .padding(.vertical, 4)\n' + anchor, 1))

path = Path('CardPilot/Features/Cards/CardDetailsView.swift')
source = path.read_text()
anchor = '                            Text("\\(cardNetworkSummary(card.networks)) · •••• \\(card.lastFour)")\n                                .font(.subheadline)'
assert source.count(anchor) == 1
source = source.replace(anchor, anchor + '\n                                .padding(.vertical, 4)', 1)
start = source.index('struct BillingCycleRow: View {')
end = source.index('private struct StatusPill: View {', start)
row = source[start:end]
lines = row.splitlines(keepends=True)
row = ''.join(line + ('                    .padding(.vertical, 4)\n' if line.strip().startswith(('Label("账单 ', 'Label("还款 ')) else '') for line in lines)
if variant == 'text':
    anchor = '                    .font(.subheadline.weight(.semibold))'
    assert row.count(anchor) == 1
    row = row.replace(anchor, anchor + '\n                    .padding(.vertical, 4)', 1)
source = source[:start] + row + source[end:]
if variant == 'text':
    start = source.index('private struct StatusPill: View {')
    tail = source[start:]
    anchor = '            .padding(.vertical, 3)'
    assert tail.count(anchor) == 1
    source = source[:start] + tail.replace(anchor, '            .padding(.vertical, 7)', 1)
path.write_text(source)
print('Applied exact-flow text-padding candidate:', variant)
