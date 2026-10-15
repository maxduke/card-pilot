"""Non-shipping AX masks for causal isolation; visible layout is unchanged."""
from pathlib import Path
import sys

variant = sys.argv[1]
assert variant in ('baseline', 'mask_background', 'mask_promotion_labels', 'mask_caption_explanation')
Path('mask.txt').write_text(variant + '\nBase application/test source: b9d2215662dd4e0fdc4ea45564e4d62f941fa045\n')
if variant == 'mask_background':
    p = Path('CardPilot/Features/Cards/CardDetailsView.swift')
    s = p.read_text()
    old = '        .navigationTitle("卡片详情")'
    assert s.count(old) == 1
    s = s.replace(old, '        .accessibilityHidden(showingTransactionEditor)\n' + old)
    p.write_text(s)
if variant in ('mask_promotion_labels', 'mask_caption_explanation'):
    p = Path('CardPilot/Features/Transactions/TransactionsView.swift')
    s = p.read_text()
    start = s.index('    private var promotionSection: some View {')
    end = s.index('    private func promotionSummary(', start)
    section = s[start:end]
    if variant == 'mask_promotion_labels':
        marker = '                    .accessibilityIdentifier("allocation.toggle.\\(promotion.title)")'
        assert section.count(marker) == 1
        section = section.replace(marker, marker + '\n                    .accessibilityHidden(true)')
        marker = '                        Text(promotionSummary(promotion))\n                            .font(.caption)'
        assert section.count(marker) == 1
        section = section.replace(marker, marker + '\n                            .accessibilityHidden(true)')
    else:
        marker = '                            Text("计入金额（\\(promotion.progressCurrencyCode)）")\n                                .font(.caption)'
        assert section.count(marker) == 1
        section = section.replace(marker, marker + '\n                                .accessibilityHidden(true)')
        marker = '                Text("已报名或无需报名、金额符合条件的累计活动会预选。不可叠加的多个活动及逐笔优惠活动，请逐项确认。")\n                    .font(.caption)'
        assert section.count(marker) == 1
        section = section.replace(marker, marker + '\n                    .accessibilityHidden(true)')
    p.write_text(s[:start] + section + s[end:])
