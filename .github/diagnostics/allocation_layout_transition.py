"""Compare layout responses to the auditor's Dynamic Type transitions; never ship."""
from pathlib import Path
import sys

variant = sys.argv[1]
assert variant in ('layout_baseline', 'form_font_identity', 'flexible_confirmation_text')
path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()


def replace_once(before, after):
    global source
    assert source.count(before) == 1, before
    source = source.replace(before, after, 1)


if variant == 'form_font_identity':
    replace_once(
        '                    .scrollDismissesKeyboard(.immediately)\n',
        '                    .id(dynamicTypeSize)\n'
        '                    .scrollDismissesKeyboard(.immediately)\n',
    )
elif variant == 'flexible_confirmation_text':
    replace_once(
        '            if let selectedCard { Text(cardLabel(selectedCard)).font(.subheadline) }',
        '            if let selectedCard {\n'
        '                Text(cardLabel(selectedCard))\n'
        '                    .font(.subheadline)\n'
        '                    .fixedSize(horizontal: false, vertical: true)\n'
        '            }',
    )
    replace_once(
        '                .font(.title2.bold())\n                .monospacedDigit()\n',
        '                .font(.title2.bold())\n                .monospacedDigit()\n'
        '                .fixedSize(horizontal: false, vertical: true)\n',
    )
    replace_once(
        '            .foregroundStyle(selectedPromotionIDs.isEmpty ? Color.secondary : Color.accentColor)\n',
        '            .foregroundStyle(selectedPromotionIDs.isEmpty ? Color.secondary : Color.accentColor)\n'
        '            .fixedSize(horizontal: false, vertical: true)\n',
    )
    replace_once(
        '            Text("请检查候选活动与计入金额；点击“确认并保存”后才会写入这笔交易。")\n'
        '                .font(.caption)\n                .foregroundStyle(.secondary)\n',
        '            Text("请检查候选活动与计入金额；点击“确认并保存”后才会写入这笔交易。")\n'
        '                .font(.caption)\n                .foregroundStyle(.secondary)\n'
        '                .fixedSize(horizontal: false, vertical: true)\n',
    )
    replace_once(
        '            TextField("搜索其他促销", text: $promotionSearchText)\n',
        '            TextField("搜索其他促销", text: $promotionSearchText)\n'
        '                .fixedSize(horizontal: false, vertical: true)\n',
    )
    replace_once(
        '                                Text(promotionSummary(promotion))\n'
        '                                    .font(.caption)\n'
        '                                    .foregroundStyle(.secondary)\n',
        '                                Text(promotionSummary(promotion))\n'
        '                                    .font(.caption)\n'
        '                                    .foregroundStyle(.secondary)\n'
        '                                    .fixedSize(horizontal: false, vertical: true)\n',
    )

path.write_text(source)
