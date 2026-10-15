"""Attribute repeated text, and compare semantic and visible long labels."""
from pathlib import Path
import re
import sys

variant = sys.argv[1]
assert variant in ('identified_baseline', 'short_input_label', 'short_visible_title')
path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
marker = '    private var promotionSection: some View {'
before, section = source.split(marker, 1)
summary = 'Text(promotionSummary(promotion))\n'
assert section.count(summary) == 2
section = re.sub(
    r'(?m)^( *)Text\(promotionSummary\(promotion\)\)\n',
    lambda match: match[0] + match[1] + '    .accessibilityIdentifier("allocation.summary.\\(promotion.title)")\n',
    section,
)
caption = '                            Text("计入金额（\\(promotion.progressCurrencyCode)）")\n'
assert section.count(caption) == 1
section = section.replace(caption, caption + '                                .accessibilityIdentifier("allocation.caption.\\(promotion.title)")\n', 1)
if variant == 'short_input_label':
    label = '                            .accessibilityLabel("\\(promotion.title)计入金额（\\(promotion.progressCurrencyCode)）")'
    assert section.count(label) == 1
    section = section.replace(label, '                            .accessibilityLabel("计入金额")', 1)
elif variant == 'short_visible_title':
    title = '                            Text(promotion.title)'
    assert section.count(title) == 1
    replacement = '                            Text(promotion.title == "星河信用卡境内外旅行住宿与日常消费累计达标返现活动" ? "首项活动" : promotion.title)'
    section = section.replace(title, replacement, 1)
path.write_text(before + marker + section)
