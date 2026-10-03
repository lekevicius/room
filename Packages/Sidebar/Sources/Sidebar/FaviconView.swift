import AppKit
import Design

/// An entry's icon: the favicon, or a letter tile (first letter of the
/// domain on a colour hashed from it, spec §I.2); dimmed while unloaded,
/// with the changed dot (§I.8), and a ring spinner in its place while the
/// page loads (§I.2).
final class FaviconView: NSView {
    var image: NSImage? { didSet { if image !== oldValue { needsDisplay = true } } }
    /// Domain the letter tile is drawn from.
    var letterSource = "" { didSet { if letterSource != oldValue { needsDisplay = true } } }
    var isUnloaded = false { didSet { alphaValue = isUnloaded ? SidebarMetrics.unloadedIconAlpha : 1 } }
    var showsChangedDot = false { didSet { dot.isHidden = !showsChangedDot } }
    var isLoading = false { didSet { if isLoading != oldValue { updateSpinner() } } }

    private let dot = CALayer()
    private let spinner = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.isHidden = true
        dot.cornerRadius = SidebarMetrics.changedDotSize / 2
        spinner.fillColor = nil
        spinner.lineWidth = 2
        spinner.lineCap = .round
        spinner.strokeStart = 0
        spinner.strokeEnd = 0.7
        spinner.isHidden = true
        layer?.addSublayer(spinner)
        layer?.addSublayer(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let size = SidebarMetrics.changedDotSize
        dot.frame = CGRect(x: bounds.maxX - size + 2, y: bounds.maxY - size + 2, width: size, height: size)
        spinner.frame = bounds
        spinner.path = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.backgroundColor = Palette.accent.cgColor
            spinner.strokeColor = NSColor.secondaryLabelColor.cgColor
        }
        guard !isLoading else { return }
        if let image {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        Self.drawLetterTile(letterSource, in: bounds)
    }

    static func drawLetterTile(_ domain: String, in rect: NSRect) {
        letterTile(domain, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                                  hints: nil)
    }

    /// Letter tiles by letter, colour and size: rendering the glyph on every
    /// draw was a visible share of each scrolled-in row (2.2b profile).
    private static var letterTiles: [String: NSImage] = [:]

    private static func letterTile(_ domain: String, size: NSSize) -> NSImage {
        let letter = domain.first.map { String($0).uppercased() } ?? "•"
        let color = Palette.letterTileColor(for: domain)
        let key = "\(letter)|\(color.hash)|\(size.width)x\(size.height)|\(NSAppearance.currentDrawing().isDark)"
        if let image = letterTiles[key] { return image }
        let image = NSImage(size: size, flipped: true) { rect in
            renderLetterTile(letter, color: color, in: rect)
            return true
        }
        if letterTiles.count > 512 { letterTiles.removeAll() }
        letterTiles[key] = image
        return image
    }

    private static func renderLetterTile(_ letter: String, color: NSColor, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.25, yRadius: rect.height * 0.25)
        color.setFill()
        path.fill()
        let font = NSFont.systemFont(ofSize: rect.height * 0.62, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (letter as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (letter as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func updateSpinner() {
        spinner.isHidden = !isLoading
        needsDisplay = true
        spinner.removeAllAnimations()
        guard isLoading, !Motion.reduceMotion else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 0.9
        spin.repeatCount = .infinity
        spinner.add(spin, forKey: "spin")
    }
}
