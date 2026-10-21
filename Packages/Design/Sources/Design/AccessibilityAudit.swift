import AppKit

/// A view that takes clicks only to dismiss what is over it (a dimmed
/// backdrop behind the palette, Peek or a dialog): Esc does the same, so
/// the accessibility tree leaves it out and the self-audit does not count it
/// as a hidden click target.
@MainActor
public protocol AccessibilityBackdrop: NSView {}

/// The accessibility self-audit (5.3a, ROADMAP 5.3 task 1): walks the tree
/// VoiceOver would read, through the NSAccessibility protocol of the elements
/// themselves, in-process (no AX client API, so no trust prompt and no other
/// app's tree), and reports what an assistive client could not use:
/// - **no label:** an interactive element (a button, a field, a row, a
///   slider, a pop-up…) with no label, title, placeholder, title element or,
///   for a row or a button, no text inside it;
/// - **generic role:** an element with no role or `AXUnknown`, or a custom
///   view that answers a press but calls itself a group, an image or text;
/// - **hidden click target:** a view of Room's own that takes clicks
///   (overrides `mouseDown(with:)`) while the tree shows neither it nor an
///   element around it (`AccessibilityBackdrop`s and views that only move the
///   window excepted).
/// AppKit's own private elements (the window's buttons, scroller parts,
/// table columns, remote views) are walked but not judged: they are named
/// by their subroles, and Room cannot change them.
/// The window-tier test (`AccessibilityAuditTests`) fails on any finding; the
/// `a11y` spike runs it over the real app's windows (`App/Sources/Debug`).
public enum AccessibilityAudit {
    public enum Problem: String, Sendable {
        case noLabel = "no label"
        case genericRole = "generic role"
        case hiddenClickTarget = "hidden click target"
    }

    public struct Finding: Hashable, Sendable, CustomStringConvertible {
        public let problem: Problem
        public let role: String
        /// The element's place: its ancestors' identifiers (or classes) and its own.
        public let path: String
        public var description: String { "\(problem.rawValue): \(role) at \(path)" }
    }

    public struct Report: Sendable {
        public var elements = 0
        public var interactive = 0
        public var findings: [Finding] = []
        /// One line per element (`dump`): depth, role, name, value, identifier.
        public var lines: [String] = []

        public init() {}

        public mutating func merge(_ other: Report) {
            elements += other.elements
            interactive += other.interactive
            for finding in other.findings where !findings.contains(finding) { findings.append(finding) }
            lines += other.lines
        }

        public var summary: String { "elements=\(elements) interactive=\(interactive) findings=\(findings.count)" }
    }

    /// Roles an assistive client operates: each needs a name.
    public static let interactiveRoles: Set<NSAccessibility.Role> = [
        .button, .checkBox, .radioButton, .popUpButton, .menuButton, .textField, .textArea, .comboBox, .slider,
        .link, .disclosureTriangle, .incrementor, .colorWell, .row, .tabGroup,
    ]

    /// Roles that say nothing about what an element does.
    static let genericRoles: Set<NSAccessibility.Role> = [.unknown, .group, .image, .staticText, .layoutArea, .layoutItem]

    /// Subtrees the audit does not enter: the engine's page (the site's own
    /// tree, Chromium's `BrowserAccessibilityCocoa`) is the page's, not
    /// Room's; a remote element lives in another process.
    static let skippedClassNames = ["RenderWidgetHostViewCocoa", "WebContentsViewCocoa", "BrowserAccessibilityCocoa", "RemoteUIElement"]

    /// AppKit's private elements: walked, never judged.
    static func isAppKitPrivate(_ object: NSObject) -> Bool {
        let name = NSStringFromClass(type(of: object))
        return name.hasPrefix("_NS") || name.hasPrefix("NSAccessibility") || name.hasPrefix("NSTheme")
            || ["NSTableRow", "NSOutlineRow", "NSTableColumn", "NSSearchButtonCellProxy"].contains(where: name.hasPrefix)
    }

    /// SwiftUI builds its accessibility tree only once an assistive client
    /// asks the app for it (VoiceOver sets `AXEnhancedUserInterface` on the
    /// application element); the audit sets it on the app's own behalf, in
    /// its own process (nothing systemwide). The engine may build its pages'
    /// trees from then on too (the cost is the audit run's only).
    public static func requestTree() {
        // The informal setter (deprecated as API, still how a client's attribute reaches the app).
        _ = NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }

    /// Audits a window: its accessibility tree and its views' click targets.
    /// `dump`: also one line per element, for the record.
    public static func audit(_ window: NSWindow, dump: Bool = false) -> Report {
        var report = audit(element: window, dump: dump)
        if let root = window.contentView?.superview ?? window.contentView {
            report.merge(clickTargets(in: root))
        }
        return report
    }

    /// Audits the tree under `element` (an `NSView`, an `NSWindow`, any NSAccessibility element).
    public static func audit(element: Any, dump: Bool = false) -> Report {
        var walker = Walker(dump: dump)
        walker.visit(element, path: [], depth: 0)
        return walker.report
    }

    // MARK: The tree

    private struct Walker {
        let dump: Bool
        var report = Report()
        var visited: Set<ObjectIdentifier> = []

        init(dump: Bool) { self.dump = dump }

        mutating func visit(_ element: Any, path: [String], depth: Int) {
            guard depth < 80, let object = element as? NSObject, visited.insert(ObjectIdentifier(object)).inserted else { return }
            let name = NSStringFromClass(type(of: object))
            if AccessibilityAudit.skippedClassNames.contains(where: name.contains) { return }
            let node = Node(object)
            var path = path
            var childDepth = depth
            if node.isElement {
                report.elements += 1
                path.append(node.pathComponent)
                if dump { report.lines.append(String(repeating: "  ", count: path.count - 1) + node.line) }
                if !AccessibilityAudit.isAppKitPrivate(object) { check(node, path: path) }
                childDepth += 1
            }
            for child in node.children { visit(child, path: path, depth: childDepth) }
        }

        mutating func check(_ node: Node, path: [String]) {
            let role = node.role
            let place = path.suffix(4).joined(separator: " › ")
            guard let role, role != .unknown, !role.rawValue.isEmpty else {
                report.findings.append(Finding(problem: .genericRole, role: role?.rawValue ?? "nil", path: place))
                return
            }
            if node.overridesPress, AccessibilityAudit.genericRoles.contains(role) {
                report.findings.append(Finding(problem: .genericRole, role: role.rawValue + " (answers a press)", path: place))
                return
            }
            guard AccessibilityAudit.interactiveRoles.contains(role) || node.overridesPress else { return }
            report.interactive += 1
            if !node.hasName {
                report.findings.append(Finding(problem: .noLabel, role: role.rawValue, path: place))
            }
        }
    }

    /// One element read through the protocol, or, for objects that only
    /// implement its methods (SwiftUI's nodes) or only the older attribute
    /// API (AppKit's table columns), through those.
    struct Node {
        let object: NSObject

        init(_ object: NSObject) { self.object = object }

        private func object(_ selector: String, attribute: String? = nil) -> Any? {
            let sel = NSSelectorFromString(selector)
            if object.responds(to: sel), let value = object.perform(sel)?.takeUnretainedValue() { return value }
            guard let attribute else { return nil }
            let legacy = NSSelectorFromString("accessibilityAttributeValue:")
            guard object.responds(to: legacy) else { return nil }
            return object.perform(legacy, with: attribute)?.takeUnretainedValue()
        }

        private func string(_ selector: String, attribute: String? = nil) -> String? {
            let value = object(selector, attribute: attribute)
            if let string = value as? String { return string.isEmpty ? nil : string }
            if let attributed = value as? NSAttributedString { return attributed.string.isEmpty ? nil : attributed.string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }

        var isElement: Bool {
            if let element = object as? NSAccessibilityProtocol { return element.isAccessibilityElement() }
            // SwiftUI's nodes and AppKit's legacy elements are returned as children: already elements.
            return true
        }

        var role: NSAccessibility.Role? { string("accessibilityRole", attribute: "AXRole").map { NSAccessibility.Role(rawValue: $0) } }

        var subrole: String? { string("accessibilitySubrole", attribute: "AXSubrole") }

        var children: [Any] {
            if let element = object as? NSAccessibilityProtocol { return element.accessibilityChildren() ?? [] }
            return (object("accessibilityChildren", attribute: "AXChildren") as? [Any]) ?? []
        }

        var label: String? {
            string("accessibilityLabel", attribute: "AXDescription") ?? string("accessibilityTitle", attribute: "AXTitle")
        }

        var value: String? { string("accessibilityValue", attribute: "AXValue") }

        var identifier: String? {
            if let identifier = string("accessibilityIdentifier") { return identifier }
            // A control's cell stands for it in the tree: the control's identifier.
            if let cell = object as? NSCell, let control = cell.controlView, !control.accessibilityIdentifier().isEmpty {
                return control.accessibilityIdentifier()
            }
            return nil
        }

        /// A custom class (not AppKit's control) that implements the press action itself.
        var overridesPress: Bool {
            let selector = #selector(NSAccessibilityProtocol.accessibilityPerformPress)
            guard let view = object as? NSView, !(view is NSControl) else { return false }
            return class_getMethodImplementation(type(of: view), selector) != class_getMethodImplementation(NSView.self, selector)
        }

        /// What VoiceOver would say for it: a label or title; a field's
        /// placeholder; the title element a form points at; for a row or a
        /// button, the text inside it.
        var hasName: Bool {
            if label != nil { return true }
            if string("accessibilityPlaceholderValue", attribute: "AXPlaceholderValue") != nil { return true }
            if let title = object("accessibilityTitleUIElement", attribute: "AXTitleUIElement") as? NSObject,
               Node(title).label != nil || Node(title).value != nil {
                return true
            }
            if [.row, .radioButton, .checkBox, .button, .popUpButton].contains(role) { return descendantText(depth: 0) }
            return false
        }

        /// A row (or a SwiftUI button wrapping its text) named by the text inside it.
        private func descendantText(depth: Int) -> Bool {
            guard depth < 6 else { return false }
            for child in children {
                guard let object = child as? NSObject else { continue }
                let node = Node(object)
                if node.label != nil { return true }
                if node.role == .staticText, node.value != nil { return true }
                if node.descendantText(depth: depth + 1) { return true }
            }
            return false
        }

        var pathComponent: String {
            if let identifier { return identifier }
            let name = NSStringFromClass(type(of: object))
            let short = name.split(separator: ".").last.map(String.init) ?? name
            let label = self.label.map { "\"\($0.prefix(24))\"" } ?? ""
            return short.prefix(32) + label
        }

        var line: String {
            var parts = [role?.rawValue ?? "nil"]
            if let subrole { parts.append("(\(subrole))") }
            if let label { parts.append("\"\(label.prefix(60))\"") }
            if let value { parts.append("= \(value.prefix(80))") }
            if let identifier { parts.append("#\(identifier)") }
            return parts.joined(separator: " ")
        }
    }

    // MARK: Click targets

    /// Room's own views that take clicks while the tree hides them: a view
    /// overriding `mouseDown(with:)` that is not an element itself and has no
    /// element ancestor of an interactive (or structural, such as a splitter
    /// or a list) role. Views that only move the window (`mouseDownCanMoveWindow`)
    /// and backdrops (`AccessibilityBackdrop`) are not targets.
    static func clickTargets(in root: NSView) -> Report {
        var report = Report()
        let selector = #selector(NSView.mouseDown(with:))
        /// The class whose own method `cls` runs (an `NSHostingView` subclass of ours runs SwiftUI's, not ours).
        func definingClass(_ cls: AnyClass, _ selector: Selector) -> AnyClass? {
            guard let imp = class_getMethodImplementation(cls, selector) else { return nil }
            var owner: AnyClass = cls
            while let parent = class_getSuperclass(owner), class_getMethodImplementation(parent, selector) == imp { owner = parent }
            return owner
        }
        func exposedAncestor(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let candidate = current {
                if candidate.isAccessibilityElement(), let role = candidate.accessibilityRole(), !genericRoles.contains(role) { return true }
                current = candidate.superview
            }
            return false
        }
        func walk(_ view: NSView, path: [String]) {
            guard !view.isHidden, view.alphaValue > 0 else { return }
            let name = NSStringFromClass(type(of: view))
            if skippedClassNames.contains(where: name.contains) || view is AccessibilityBackdrop { return }
            let path = path + [view.accessibilityIdentifier().isEmpty ? (name.split(separator: ".").last.map(String.init) ?? name) : view.accessibilityIdentifier()]
            if !(view is NSControl), let owner = definingClass(type(of: view), selector), owner != NSView.self,
               !Bundle(for: owner).bundlePath.hasPrefix("/System/"), !view.mouseDownCanMoveWindow, !exposedAncestor(view) {
                report.findings.append(Finding(problem: .hiddenClickTarget, role: view.accessibilityRole()?.rawValue ?? "nil",
                                               path: path.suffix(4).joined(separator: " › ")))
            }
            for subview in view.subviews { walk(subview, path: path) }
        }
        walk(root, path: [])
        return report
    }
}
