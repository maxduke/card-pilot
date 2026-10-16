"""Read-only public UIKit metrics for the original audit flow; diagnostic branch only."""
from pathlib import Path

path = Path('CardPilot/Features/Transactions/TransactionsView.swift')
source = path.read_text()
assert source.count('import SwiftUI\n') == 1
source = source.replace('import SwiftUI\n', 'import SwiftUI\nimport UIKit\n', 1)
marker = '                    .accessibilityIdentifier("transaction.form")\n'
assert source.count(marker) == 1
source = source.replace(marker, marker + r'''
                    .background(AllocationNativeAuditProbe(state: "\(dynamicTypeSize)|step=\(editorStep)|errors=\(showingAllocationErrors)"))
''', 1)
source += r'''

// Diagnostic observer only. Never merge into application delivery branches.
@MainActor
private struct AllocationNativeAuditProbe: UIViewRepresentable {
    let state: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let capturedState = state
        DispatchQueue.main.async {
            guard let scene = uiView.window?.windowScene else { return }
            print("AllocationNativeAuditProbe BEGIN state=\(capturedState) time=\(Date().timeIntervalSince1970)")
            for window in scene.windows {
                var visited = 0
                Self.inspect(window, window: window, ancestorsVisible: true,
                             clip: window.bounds, path: "", visited: &visited)
            }
            print("AllocationNativeAuditProbe END")
        }
    }

    private static func inspect(_ view: UIView, window: UIWindow, ancestorsVisible: Bool,
                                clip: CGRect, path: String, visited: inout Int) {
        guard visited < 5000 else { return }
        visited += 1
        let name = String(reflecting: type(of: view))
        let ancestry = String((path + "/" + name).suffix(220))
        let visible = ancestorsVisible && !view.isHidden && view.alpha > 0.01
        let rect = view.convert(view.bounds, to: window)
        let visibleRect = rect.intersection(clip)
        let common = "class=\(name) id=\(view.accessibilityIdentifier ?? "nil") bounds=\(view.bounds) window=\(rect) visible=\(visible) viewport=\(visibleRect) isAX=\(view.isAccessibilityElement) path=\(ancestry)"
        if let label = view as? UILabel {
            let fit = label.sizeThatFits(CGSize(width: max(1, label.bounds.width), height: CGFloat.greatestFiniteMagnitude))
            print("AllocationNativeAuditProbe UILabel \(common) text=\(String(reflecting: label.text ?? "")) font=\(label.font.pointSize) lineHeight=\(label.font.lineHeight) lines=\(label.numberOfLines) break=\(label.lineBreakMode.rawValue) fit=\(fit) shrinks=\(label.adjustsFontSizeToFitWidth)")
        }
        if let field = view as? UITextField {
            let textRect = field.textRect(forBounds: field.bounds)
            print("AllocationNativeAuditProbe UITextField \(common) text=\(String(reflecting: field.text ?? "")) placeholder=\(String(reflecting: field.placeholder ?? "")) font=\(field.font?.pointSize ?? -1) lineHeight=\(field.font?.lineHeight ?? -1) textRect=\(textRect) editing=\(field.isEditing)")
        }
        let nextClip = view.clipsToBounds ? clip.intersection(rect) : clip
        for child in view.subviews {
            inspect(child, window: window, ancestorsVisible: visible,
                    clip: nextClip, path: ancestry, visited: &visited)
        }
    }
}
'''
path.write_text(source)
