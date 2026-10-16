// Standalone diagnostic reference only. Never include in application delivery.
private struct AllocationAuditReference: View {
    let scope: String
    @State private var showsSheet = false

    var body: some View {
        NavigationStack {
            if scope.hasPrefix("sheet-") {
                Button("打开审计对照") { showsSheet = true }
                    .accessibilityIdentifier("allocation.reference.open")
                    .navigationTitle("对照入口")
            } else {
                referenceForm
            }
        }
        .sheet(isPresented: $showsSheet) {
            NavigationStack {
                referenceForm
            }
        }
    }

    private var referenceForm: some View {
        Form {
            Section("促销分配") {
                if scope == "sheet-clipped" {
                    AllocationReferenceClippedLabel()
                        .frame(width: 120, height: 32)
                } else {
                    ForEach(0..<(scope == "root-one" ? 1 : 8), id: \.self) { index in
                        Text("CNY · 达标 1,000")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("allocation.reference.text.\(index)")
                    }
                }
            }
        }
        .accessibilityIdentifier("allocation.reference.form")
        .navigationTitle("审计对照")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AllocationReferenceClippedLabel: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var size

    func makeUIView(context: Context) -> AllocationReferenceNativeLabel {
        let label = AllocationReferenceNativeLabel()
        label.text = "裁切对照"
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontSizeToFitWidth = false
        label.adjustsFontForContentSizeCategory = true
        label.clipsToBounds = true
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "allocation.reference.clipped"
        label.backgroundColor = .systemYellow
        return label
    }

    func updateUIView(_ uiView: AllocationReferenceNativeLabel, context: Context) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        uiView.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AllocationReferenceNativeLabel, context: Context) -> CGSize? {
        CGSize(width: 120, height: 32)
    }
}

private final class AllocationReferenceNativeLabel: UILabel {
    override func layoutSubviews() {
        super.layoutSubviews()
        print("AllocationReferenceNativeLabel category=\(traitCollection.preferredContentSizeCategory.rawValue) font=\(font.pointSize) lineHeight=\(font.lineHeight) bounds=\(bounds)")
    }
}
