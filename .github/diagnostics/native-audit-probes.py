import os,subprocess
from pathlib import Path
variant = os.environ['AUDIT_VARIANT']
assert variant in ('status','month','dates','header_meta','account_meta','a11y_ignore','a11y_default')
subprocess.run(['git','apply','--unidiff-zero','.github/diagnostics/date-navigation.patch'],check=True)
path=Path('CardPilot/Features/Cards/CardDetailsView.swift');source=path.read_text()
if variant=='header_meta':
    anchor='                            Text("\\(cardNetworkSummary(card.networks)) · •••• \\(card.lastFour)")'
    assert source.count(anchor)>=1
    source=source.replace(anchor,anchor+'\n                                .hidden()',1)
elif variant=='account_meta':
    start=source.index('            Section("账单日程") {');end=source.index('            Section("适用活动") {',start)
    section=source[start:end];anchor='                    .padding(.vertical, 5)'
    assert section.count(anchor)==1
    source=source[:start]+section.replace(anchor,anchor+'\n                    .hidden()',1)+source[end:]
else:
    start=source.index('struct BillingCycleRow: View {');end=source.index('private struct StatusPill: View {',start)
    row=source[start:end]
    if variant=='a11y_ignore':
        anchor='        .accessibilityElement(children: .combine)'
        assert row.count(anchor)==1
        row=row.replace(anchor,'        .accessibilityElement(children: .ignore)',1)
    elif variant=='a11y_default':
        row='\n'.join(line for line in row.split('\n') if '.accessibilityLabel(' not in line)
    elif variant=='status':
        anchor='                StatusPill(title: statusTitle, color: statusColor)'
    elif variant=='month':
        anchor='                Text("\\(CardPilotUI.monthKeyText(cycle.cycleKey))账期")'
    else:
        anchor=next(line for line in row.splitlines() if line.strip().startswith('Text("账单 '))
    if not variant.startswith('a11y_'):
        assert row.count(anchor)==1
        row=row.replace(anchor,anchor+'\n                    .hidden()',1)
    source=source[:start]+row+source[end:]
path.write_text(source)
print('Layout-preserving text isolation:',variant)
