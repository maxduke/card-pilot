"""Compare validation row updates and scroll ordering; diagnostic only."""
from pathlib import Path
import sys

part = sys.argv[1]
assert part in ('deferred-scroll', 'separate-error', 'combined')


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
if part in ('separate-error', 'combined'):
    start = source.index('    private var promotionSection: some View {')
    end = source.index('    private func promotionSummary(', start)
    section = source[start:end]
    marker = '                        let warning = qualificationWarning(for: promotion)\n'
    section = once(section, marker, marker + '                        let hasError = showingAllocationErrors && positiveAllocationAmount(for: promotion.id) == nil\n')
    marker = '''                            if showingAllocationErrors && positiveAllocationAmount(for: promotion.id) == nil {
                                InlineErrorView(message: "计入金额应为大于 0 的数字。")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("allocation.error.\\(promotion.title)")
                            }
'''
    section = once(section, marker, '')
    marker = '                        .listRowSeparator(warning == nil ? .visible : .hidden, edges: .bottom)\n'
    section = once(section, marker, '                        .listRowSeparator(hasError || warning != nil ? .hidden : .visible, edges: .bottom)\n')
    marker = '                        .id(InputField.allocation(promotion.id))\n'
    section = once(section, marker, marker + '''                        if hasError {
                            InlineErrorView(message: "计入金额应为大于 0 的数字。")
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 24)
                                .listRowSeparator(warning == nil ? .visible : .hidden, edges: .bottom)
                                .accessibilityIdentifier("allocation.error.\\(promotion.title)")
                        }
''')
    source = source[:start] + section + source[end:]

if part in ('deferred-scroll', 'combined'):
    marker = '''                showingAllocationErrors = true
                scrollProxy.scrollTo(InputField.allocation(promotion.id), anchor: .top)
'''
    source = once(source, marker, '''                showingAllocationErrors = true
                let field = InputField.allocation(promotion.id)
                Task { @MainActor in
                    await Task.yield()
                    scrollProxy.scrollTo(field, anchor: .top)
                }
''')
path.write_text(source)
