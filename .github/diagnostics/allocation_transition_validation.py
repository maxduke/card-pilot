"""Validate native transition candidates and an intentional clipping control; never ship."""
from pathlib import Path
import sys

variant = sys.argv[1]
assert variant in ('identity_preserves_input', 'identity_clipping_control', 'animation_preserves_input')
path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
marker = '                    .scrollDismissesKeyboard(.immediately)\n'
assert source.count(marker) == 1
modifier = '.animation(nil, value: dynamicTypeSize)' if variant == 'animation_preserves_input' else '.id(dynamicTypeSize)'
source = source.replace(marker, '                    ' + modifier + '\n' + marker, 1)

if variant == 'identity_clipping_control':
    marker = '                            if showingAllocationErrors && positiveAllocationAmount(for: promotion.id) == nil {\n'
    assert source.count(marker) == 1
    control = '''                            if promotion.title == "星河信用卡境内外旅行住宿与日常消费累计达标返现活动" {
                                Text("诊断：这段文字应触发裁切")
                                    .font(.body)
                                    .lineLimit(1)
                                    .frame(width: 24, height: 12, alignment: .leading)
                                    .clipped()
                                    .accessibilityIdentifier("allocation.diagnostic.clippingControl")
                            }
'''
    source = source.replace(marker, control + marker, 1)
path.write_text(source)

if variant != 'identity_clipping_control':
    path = Path('CardPilotUITests/CoreFlowsUITests.swift')
    source = path.read_text()
    start = source.index('    func testAllocationErrorLocationAndCompletePromptAtLargestTextSize() throws {')
    end = source.index('    func testTransactionAllocationPersistsAndUpdatesPromotion()', start)
    case = source[start:end]
    # Additional real UI checks after the original complete audit. Keep the
    # original audit, handler, invalid input, and every preceding assertion.
    closing = '        }\n    }\n\n'
    assert case.endswith(closing)
    checks = '''        XCTAssertFalse(app.keyboards.firstMatch.exists)
        reveal(first, scrollTowardTopWhenMissing: true, navigationBar: navigationBar, contentHeader: progress)
        assertAllocationErrorVisible(allocationFeedbackFirstTitle)
        XCTAssertEqual(first.value as? String, "0")
        XCTAssertEqual(error.label, "错误：计入金额应为大于 0 的数字。")
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(back.isHittable)
        captureScreenshot("字号审计后保留输入与完整错误")
'''
    case = case[:-len(closing)] + '        }\n' + checks + '    }\n\n'
    source = source[:start] + case + source[end:]
    path.write_text(source)
