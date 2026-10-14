"""Throwaway native experiments; never merge this diagnostic branch."""
from pathlib import Path
import sys

variant = sys.argv[1]
assert variant in ('baseline', 'stable_rows', 'decorative_icon')
if variant == 'stable_rows':
    path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
    source = path.read_text()
    old = '''                            if !dynamicTypeSize.isAccessibilitySize {
                                Text(promotionSummary(promotion))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
'''
    assert source.count(old) == 1
    source = source.replace(old, '', 1)
    old = '''                    if dynamicTypeSize.isAccessibilitySize {
                        // A long title and its summary can exceed the entire
                        // viewport together. Let each native row scroll fully
                        // into view without reducing either text's size.
                        Text(promotionSummary(promotion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowSeparator(selectedPromotionIDs.contains(promotion.id) ? .hidden : .visible, edges: .bottom)
                    }
'''
    assert source.count(old) == 1
    new = '''                    Text(promotionSummary(promotion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowSeparator(selectedPromotionIDs.contains(promotion.id) ? .hidden : .visible, edges: .bottom)
'''
    source = source.replace(old, new, 1)
    source = source.replace('.listRowSeparator(dynamicTypeSize.isAccessibilitySize || selectedPromotionIDs.contains(promotion.id) ? .hidden : .visible, edges: .bottom)', '.listRowSeparator(.hidden, edges: .bottom)', 1)
    path.write_text(source)
if variant == 'decorative_icon':
    path = Path('CardPilot/Features/Shared/Formatting.swift')
    source = path.read_text()
    marker = 'struct InlineErrorView: View {'
    before, error = source.split(marker, 1)
    old = '            Image(systemName: "exclamationmark.triangle")'
    assert error.count(old) == 1
    error = error.replace(old, old + '\n                .accessibilityHidden(true)', 1)
    path.write_text(before + marker + error)
