"""Split allocation Form contents and calibrate a known native clipping control."""
from pathlib import Path
import subprocess
import sys

part = sys.argv[1]
assert part in ('summary', 'promotions', 'plain', 'control')
subprocess.run([sys.executable, str(Path(__file__).with_name('allocation_foreground_scope.py')), 'form'], check=True)


def once(source, marker, replacement):
    assert source.count(marker) == 1, marker
    return source.replace(marker, replacement, 1)


path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
source = once(source, 'import SwiftUI\n', 'import SwiftUI\nimport UIKit\n')
marker = '    private let diagnosticAuditScope = "form"\n'
source = once(source, marker, marker + f'    private let diagnosticFormPart = "{part}"\n')
marker = '                    if !diagnosticReduced || diagnosticAuditScope == "form" {\n'
source = once(source, marker, '                    if !diagnosticReduced || diagnosticFormPart == "summary" || diagnosticFormPart == "promotions" {\n')
start = source.index('    private var promotionConfirmationSections: some View {')
end = source.index('    private func continueToPromotionConfirmation()', start)
section = source[start:end]
marker = '        Section("本笔交易") {\n'
section = once(section, marker, '        if !diagnosticReduced || diagnosticFormPart == "summary" {\n' + marker)
marker = '        promotionSection\n'
section = once(section, marker, '''        }
        if !diagnosticReduced || diagnosticFormPart == "promotions" {
            promotionSection
        }
''')
source = source[:start] + section + source[end:]
marker = '                    .accessibilityIdentifier("transaction.form")\n                    }\n'
source = once(source, marker, marker + '''                    if diagnosticReduced && (diagnosticFormPart == "plain" || diagnosticFormPart == "control") {
                        Form {
                            if diagnosticFormPart == "control" {
                                AllocationKnownClippingControl()
                                    .frame(width: 120, height: 32)
                            } else {
                                Text("诊断静态页面")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("allocation.diagnostic.fresh.form")
                    }
''')
source += '''
// Diagnostic positive control only. Never include in production delivery.
@MainActor
private struct AllocationKnownClippingControl: UIViewRepresentable {
    @Environment(\\.dynamicTypeSize) private var size

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.text = "裁切对照"
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontSizeToFitWidth = false
        label.adjustsFontForContentSizeCategory = true
        label.clipsToBounds = true
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "allocation.diagnostic.knownClipping"
        label.backgroundColor = .systemYellow
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        uiView.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        print("AllocationKnownClippingControl category=\\(size) font=\\(uiView.font.pointSize) lineHeight=\\(uiView.font.lineHeight) bounds=\\(uiView.bounds)")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        CGSize(width: 120, height: 32)
    }
}
'''
path.write_text(source)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
source = once(source, 'captureScreenshot("前景审计范围-form")', f'captureScreenshot("表单审计范围-{part}")')
path.write_text(source)
