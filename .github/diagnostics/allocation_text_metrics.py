"""Record native font measurements without moving or filtering the audit."""
from pathlib import Path

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
marker = '        let beforeAudit = XCTAttachment(string: app.debugDescription)'
assert source.count(marker) == 1
metrics = '''        let metricTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let metricWidth = error.frame.width
        var metricLines = ["Error AX frame: \\(error.frame); measurement width: \\(metricWidth)"]
        for style in [UIFont.TextStyle.footnote, .body, .caption1] {
            let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: metricTraits)
            for text in ["计入金额应为大于 0 的数字。", error.label, "搜索其他促销"] {
                let measured = (text as NSString).boundingRect(
                    with: CGSize(width: metricWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font], context: nil
                )
                metricLines.append("\\(style.rawValue) \\(font.pointSize)pt / line \\(font.lineHeight): \\(text) -> \\(measured)")
            }
        }
        let metricsAttachment = XCTAttachment(string: metricLines.joined(separator: "\\n"))
        metricsAttachment.name = "原生错误文字测量诊断"
        metricsAttachment.lifetime = .keepAlways
        add(metricsAttachment)
'''
path.write_text(source.replace(marker, metrics + marker, 1))
