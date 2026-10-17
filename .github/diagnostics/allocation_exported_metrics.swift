// Diagnostic observer only. Never merge into application delivery branches.
@MainActor
private struct AllocationExportedMetrics: UIViewRepresentable {
    let state: String

    func makeUIView(context: Context) -> AllocationMetricsView {
        AllocationMetricsView(frame: .zero)
    }

    func updateUIView(_ uiView: AllocationMetricsView, context: Context) {
        uiView.state = state
        DispatchQueue.main.async { [weak uiView] in
            uiView?.capture("swiftui.update")
        }
    }
}

@MainActor
private final class AllocationMetricsView: UIView {
    var state = ""
    private var previousLayout = ""
    private var lastLayoutCapture: TimeInterval = 0
    private let fileName = "native-\(UUID().uuidString).jsonl"

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(categoryChanged),
            name: UIContentSizeCategory.didChangeNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("Not used by diagnostic observer") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let signature = "\(state)|\(traitCollection.preferredContentSizeCategory.rawValue)|\(bounds)"
        let now = Date().timeIntervalSince1970
        if signature != previousLayout, now - lastLayoutCapture > 0.1 {
            previousLayout = signature
            lastLayoutCapture = now
            capture("probe.layout")
        }
    }

    @objc private func categoryChanged(_ notification: Notification) {
        capture("category.notification")
        // Observe transitions and their settled states without requesting layout.
        for delay in [0.0, 0.05, 0.25, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.capture("category.after.\(delay)")
            }
        }
    }

    func capture(_ event: String) {
        guard state.contains("step=1|errors=true"),
              let scene = window?.windowScene else { return }
        var views: [[String: Any]] = []
        for window in scene.windows {
            var visited = 0
            Self.inspect(window, window: window, visible: true, clip: window.bounds,
                         path: "", visited: &visited, result: &views)
        }
        let record: [String: Any] = [
            "time": Date().timeIntervalSince1970, "event": event, "state": state,
            "applicationCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "probeCategory": traitCollection.preferredContentSizeCategory.rawValue,
            "views": views,
        ]
        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AllocationNativeEvidence", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0a)
            try handle.write(contentsOf: data)
        } catch {
            print("AllocationExportedMetrics write failed: \(error)")
        }
    }

    private static func rect(_ value: CGRect) -> [String: Double] {
        guard !value.isNull, !value.isInfinite else { return [:] }
        return ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
    }

    private static func inspect(_ view: UIView, window: UIWindow, visible: Bool,
                                clip: CGRect, path: String, visited: inout Int,
                                result: inout [[String: Any]]) {
        guard visited < 5000 else { return }
        visited += 1
        let type = String(reflecting: Swift.type(of: view))
        let ancestry = String((path + "/" + type).suffix(300))
        let isVisible = visible && !view.isHidden && view.alpha > 0.01
        let frame = view.convert(view.bounds, to: window)
        let viewport = frame.intersection(clip)
        var data: [String: Any] = [
            "class": type, "id": view.accessibilityIdentifier ?? "",
            "bounds": rect(view.bounds), "frame": rect(frame),
            "visible": isVisible, "viewport": rect(viewport),
            "isAX": view.isAccessibilityElement, "path": ancestry,
            "category": view.traitCollection.preferredContentSizeCategory.rawValue,
        ]
        if let label = view as? UILabel {
            let fit = label.sizeThatFits(CGSize(width: max(1, label.bounds.width),
                                               height: CGFloat.greatestFiniteMagnitude))
            data["kind"] = "label"
            data["text"] = String((label.text ?? "").prefix(600))
            data["font"] = label.font.pointSize
            data["lineHeight"] = label.font.lineHeight
            data["fitWidth"] = fit.width
            data["fitHeight"] = fit.height
            data["lines"] = label.numberOfLines
            data["break"] = label.lineBreakMode.rawValue
            data["shrinks"] = label.adjustsFontSizeToFitWidth
            result.append(data)
        } else if let field = view as? UITextField {
            data["kind"] = "field"
            data["text"] = String((field.text ?? "").prefix(600))
            data["placeholder"] = field.placeholder ?? ""
            data["font"] = field.font?.pointSize ?? -1
            data["lineHeight"] = field.font?.lineHeight ?? -1
            data["textRect"] = rect(field.textRect(forBounds: field.bounds))
            data["editing"] = field.isEditing
            data["adjustsForCategory"] = field.adjustsFontForContentSizeCategory
            result.append(data)
        }
        let nextClip = view.clipsToBounds ? clip.intersection(frame) : clip
        for child in view.subviews {
            inspect(child, window: window, visible: isVisible, clip: nextClip,
                    path: ancestry, visited: &visited, result: &result)
        }
    }
}
