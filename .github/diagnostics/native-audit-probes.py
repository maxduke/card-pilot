import os,re
from pathlib import Path
variant = os.environ['AUDIT_VARIANT']
assert variant in ('label_text', 'sections')

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
anchor = '                    .font(.subheadline.weight(.semibold))'
assert row.count(anchor) == 1
row = row.replace(anchor, anchor + '\n                    .padding(.vertical, 4)', 1)
def label(match):
    indent,title,symbol = match.groups()
    return indent + 'Label {\n' + indent + '    Text(' + title + ')\n' + indent + '        .padding(.vertical, 4)\n' + indent + '} icon: {\n' + indent + '    Image(systemName: "' + symbol + '")\n' + indent + '}\n'
row,count = re.subn(r'^( +)Label\((.*), systemImage: "([^"]+)"\)\n', label, row, flags=re.M)
assert count == 2
source = source[:start] + row + source[end:]
start = source.index('private struct StatusPill: View {')
tail = source[start:]
anchor = '            .padding(.vertical, 3)'
assert tail.count(anchor) == 1
source = source[:start] + tail.replace(anchor, '            .padding(.vertical, 4)', 1)
path.write_text(source)

if variant == 'sections':
    path = Path('CardPilot/Features/Cards/BillingCycleDetailView.swift')
    source = path.read_text()
    anchor = '                        fieldError(.statement, issue: issue)\n                        Toggle("调整还款日", isOn: $overrideRepayment)'
    assert source.count(anchor) == 1
    source = source.replace(anchor, '                        fieldError(.statement, issue: issue)\n                    }\n                    Section {\n                        Toggle("调整还款日", isOn: $overrideRepayment)', 1)
    path.write_text(source)
print('Applied text-inside-label candidate:', variant)
