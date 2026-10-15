"""Remove candidate content structurally for diagnosis; never ship these edits."""
from pathlib import Path
import sys

scope = sys.argv[1]
assert scope in ('valid_baseline', 'no_search', 'no_background')
if scope == 'no_search':
    path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
    source = path.read_text()
    row = '            TextField("搜索其他促销", text: $promotionSearchText)\n'
    assert source.count(row) == 1
    path.write_text(source.replace(row, '', 1))
elif scope == 'no_background':
    path = Path('CardPilot/Features/Cards/CardDetailsView.swift')
    source = path.read_text()
    start = source.index('        List {\n', source.index('struct CardDetailView: View {'))
    end = source.index('        .listStyle(.insetGrouped)', start)
    rows = source[start + len('        List {\n'):end]
    assert rows.endswith('        }\n')
    rows = rows[:-len('        }\n')]
    rows = ''.join('    ' + line if line.strip() else line for line in rows.splitlines(keepends=True))
    replacement = ('        List {\n'
                   '            if !showingTransactionEditor {\n' + rows +
                   '            }\n'
                   '        }\n')
    path.write_text(source[:start] + replacement + source[end:])
