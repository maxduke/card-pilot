"""Export passive native measurements from the exact production layout."""
from pathlib import Path

path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
before = path.read_text()
source = before


def once(marker, replacement):
    global source
    assert source.count(marker) == 1, marker
    source = source.replace(marker, replacement, 1)


once('import SwiftUI\n', 'import SwiftUI\nimport UIKit\n')
marker = '                    .accessibilityIdentifier("transaction.form")\n'
probe_modifier = r'''                    .background(AllocationExportedMetrics(state: "\(dynamicTypeSize)|step=\(editorStep)|errors=\(showingAllocationErrors)"))
'''
once(marker, marker + probe_modifier)
probe = Path(__file__).with_name('allocation_exported_metrics.swift').read_text()
source += '\n' + probe
assert source.removesuffix('\n' + probe).replace(probe_modifier, '', 1).replace('import UIKit\n', '', 1) == before
path.write_text(source)
