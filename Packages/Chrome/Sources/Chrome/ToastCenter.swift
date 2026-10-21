import AppKit
import Design
import Observation
import SwiftUI

/// Shows toasts as an overlay in a window's root view (spec §F): anchored
/// bottom-centre of the sidebar while it is visible, else bottom-left of
/// the window. The toast is a SwiftUI leaf on Liquid Glass.
public final class ToastCenter: ToastPresenting {
    /// Where toasts sit, in the host view's coordinates: the bottom edge of
    /// `rect` with the toast centred or leading-aligned in it.
    public struct Anchor: Equatable {
        public var rect: CGRect
        public var alignment: Alignment

        public enum Alignment: Equatable { case center, leading }

        public init(rect: CGRect, alignment: Alignment) {
            self.rect = rect
            self.alignment = alignment
        }
    }

    public let queue: ToastQueue
    private let model = ToastModel()
    private let hostingView: ToastHostingView
    private weak var hostView: NSView?
    private let anchor: () -> Anchor
    /// Identity of the toast view: new for each toast that transitions in,
    /// kept when the same id pops.
    private var generation = 0

    /// Height of the band the toast lives in (toast plus its rise).
    static let bandHeight: CGFloat = 72

    public init(hostView: NSView, scheduler: ToastScheduler = MainQueueToastScheduler(), anchor: @escaping () -> Anchor) {
        self.hostView = hostView
        self.anchor = anchor
        queue = ToastQueue(scheduler: scheduler)
        hostingView = ToastHostingView(rootView: ToastOverlay(model: model))
        hostingView.model = model
        hostingView.setAccessibilityIdentifier("toasts")
        model.onHover = { [weak self] hovering in self?.queue.setHovering(hovering) }
        model.onAction = { [weak self] in self?.queue.performAction() }
        queue.onEvent = { [weak self] event in self?.apply(event) }
        hostView.addSubview(hostingView)
        updateAnchor()
    }

    public func show(_ toast: Toast) {
        updateAnchor()
        queue.show(toast)
    }

    /// Takes down the showing toast if it is `id` (a notice the engine withdrew).
    public func dismiss(id: String) {
        guard queue.current?.id == id else { return }
        queue.dismiss()
    }

    /// The toast on screen (spikes).
    public var currentToast: Toast? { queue.current }

    /// Call when the window or sidebar geometry changes.
    public func updateAnchor() {
        guard let hostView else { return }
        let anchor = anchor()
        let flipped = hostView.isFlipped
        let y = flipped ? anchor.rect.maxY - Self.bandHeight : anchor.rect.minY
        hostingView.frame = NSRect(x: anchor.rect.minX, y: y, width: anchor.rect.width, height: Self.bandHeight)
        model.alignment = anchor.alignment
        if hostingView.superview === hostView, hostView.subviews.last !== hostingView {
            hostView.addSubview(hostingView, positioned: .above, relativeTo: nil)
        }
    }

    private func apply(_ event: ToastQueue.Event) {
        // The transitions read these (Motion.preferences, not SwiftUI's own environment value).
        model.inVariant = ChromeMotion.toastIn.variant
        model.outVariant = ChromeMotion.toastOut.variant
        switch event {
        case .appear, .replace(_, false):
            generation += 1
            let content = queue.current.map { ToastContent($0, generation: generation) }
            withAnimation(model.inVariant == .full ? Motion.toast.swiftUI : .easeInOut(duration: Motion.fast)) {
                model.content = content
            }
        case .replace(_, true):
            model.content = queue.current.map { ToastContent($0, generation: generation) }
            if ChromeMotion.toastPop.animates { model.pops += 1 }
        case .dismiss:
            withAnimation(.easeOut(duration: Motion.toastOut)) { model.content = nil }
        }
    }
}

extension Motion.Spring {
    /// The same spring for SwiftUI.
    var swiftUI: Animation { .spring(duration: duration, bounce: bounce) }
}

/// What the SwiftUI view shows.
struct ToastContent: Equatable, Identifiable {
    var id: Int
    var symbol: Symbol?
    var message: String
    var actionTitle: String?

    init(_ toast: Toast, generation: Int) {
        id = generation
        symbol = toast.symbol
        message = toast.message
        actionTitle = toast.action?.title
    }
}

@Observable
final class ToastModel {
    var content: ToastContent?
    var alignment: ToastCenter.Anchor.Alignment = .center
    var pops = 0
    /// The in and out transitions' variants (`ChromeMotion`), set before each change.
    var inVariant = MotionVariant.full
    var outVariant = MotionVariant.full
    /// The toast's frame in the hosting view (for hit testing).
    var toastFrame: CGRect = .zero
    @ObservationIgnored var onHover: ((Bool) -> Void)?
    @ObservationIgnored var onAction: (() -> Void)?
}

/// Lets clicks outside the toast through to the sidebar or page below.
final class ToastHostingView: NSHostingView<ToastOverlay> {
    weak var model: ToastModel?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let model, model.content != nil else { return nil }
        let local = convert(point, from: superview)
        // SwiftUI reports the frame top-left based; NSHostingView is flipped.
        guard model.toastFrame.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override var mouseDownCanMoveWindow: Bool { false }
}

struct ToastOverlay: View {
    let model: ToastModel

    /// Spec §F: springs in rising and growing, leaves fading and shrinking; Reduce Motion fades both ways.
    private var transition: AnyTransition {
        let insertion: AnyTransition = model.inVariant == .full
            ? .scale(scale: Motion.toastInScale).combined(with: .opacity).combined(with: .offset(y: Motion.toastInOffset))
            : .opacity
        let removal: AnyTransition = model.outVariant == .full ? .scale(scale: Motion.toastOutScale).combined(with: .opacity) : .opacity
        return .asymmetric(insertion: insertion, removal: removal)
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let content = model.content {
                ToastView(content: content, onAction: { model.onAction?() })
                    .onHover { model.onHover?($0) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("toasts")) } action: { model.toastFrame = $0 }
                    .keyframeAnimator(initialValue: 1.0, trigger: model.pops) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(Motion.toastPopScale, duration: Motion.toastPopUp)
                        SpringKeyframe(1.0, duration: Motion.toastPopDown)
                    }
                    .id(content.id)
                    .transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.alignment == .center ? .bottom : .bottomLeading)
        .padding(.horizontal, Spacing.s)
        .padding(.bottom, Spacing.s)
        .coordinateSpace(.named("toasts"))
    }
}

struct ToastView: View {
    let content: ToastContent
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let symbol = content.symbol {
                Image(systemName: symbol.name)
                    .font(Font(Typography.toast as CTFont))
                    .foregroundStyle(.secondary)
            }
            Text(content.message)
                .font(Font(Typography.row))
                .lineLimit(1)
                .truncationMode(.tail)
            if let title = content.actionTitle {
                Button(title, action: onAction)
                    .buttonStyle(.plain)
                    .font(Font(Typography.row).weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("toast-action")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toast")
    }
}
