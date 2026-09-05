import SwiftUI

struct EditorDismissAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

struct EditorCancelButton: View {
    @Environment(\.requestEditorDismiss) private var requestDismiss

    var body: some View {
        Button("取消") { requestDismiss() }
    }
}

private struct EditorDismissKey: EnvironmentKey {
    static let defaultValue = EditorDismissAction()
}

extension EnvironmentValues {
    var requestEditorDismiss: EditorDismissAction {
        get { self[EditorDismissKey.self] }
        set { self[EditorDismissKey.self] = newValue }
    }
}

extension View {
    func protectEdits(snapshot: String) -> some View {
        modifier(EditorSessionModifier(snapshot: snapshot))
    }
}

/// Only pass value-type editor fields; sorted IDs make multi-selection order irrelevant.
func editorSnapshot(_ values: Any...) -> String {
    values.map { String(reflecting: $0) }.description
}

private struct EditorSessionModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let snapshot: String
    @State private var initialSnapshot: String?
    @State private var showingDiscardConfirmation = false

    private var hasChanges: Bool { initialSnapshot.map { $0 != snapshot } ?? false }

    func body(content: Content) -> some View {
        content
            .environment(\.requestEditorDismiss, EditorDismissAction {
                if hasChanges { showingDiscardConfirmation = true }
                else { dismiss() }
            })
            .interactiveDismissDisabled(hasChanges)
            .onAppear { if initialSnapshot == nil { initialSnapshot = snapshot } }
            .confirmationDialog("放弃未保存的修改？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("这些修改尚未保存。你也可以继续编辑，稍后再保存。")
            }
    }
}
