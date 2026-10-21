import AppKit
import Engine

/// The fake page: a read-only text view listing the URL, title and state.
final class FakePageView: NSScrollView {
    private let textView: NSTextView

    init() {
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular) // design-audit: FakeEngine's stand-in page for tests and the engine-free app, not the chrome
        textView.textContainerInset = NSSize(width: 16, height: 16)
        documentView = textView
        hasVerticalScroller = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(lines: [String]) {
        textView.string = lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var text: String { textView.string }
}

/// DevTools stand-in: a label filling the host view.
final class FakeDevTools: DevTools {
    private weak var contents: FakeWebContents?
    private var view: NSTextField?
    private(set) var inspectedPoint: NSPoint?
    private(set) var tool: DevToolsTool?
    var isDockable: Bool { true }

    init(contents: FakeWebContents) {
        self.contents = contents
    }

    var isOpen: Bool { view?.superview != nil }

    func open(in hostView: NSView) {
        let label = view ?? NSTextField(labelWithString: "")
        label.stringValue = "DevTools — \(contents?.url?.absoluteString ?? "about:blank")"
        label.frame = hostView.bounds
        label.autoresizingMask = [.width, .height]
        hostView.addSubview(label)
        view = label
    }

    func open(in hostView: NSView, tool: DevToolsTool) {
        open(in: hostView)
        self.tool = tool
    }

    func inspectElement(at point: NSPoint, in hostView: NSView) {
        open(in: hostView)
        inspectedPoint = point
    }

    func close() {
        view?.removeFromSuperview()
        view = nil
        inspectedPoint = nil
        tool = nil
    }
}
