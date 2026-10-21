import AppKit
import Design

/// An entry's icon: the favicon, or a letter tile (first letter of the
/// domain on a colour hashed from it, spec §I.2); dimmed while unloaded,
/// with the changed dot (§I.8), and a ring spinner in its place while the
/// page loads (§I.2).
public final class FaviconView: NSView {
    public var image: NSImage? { didSet { if image !== oldValue { needsDisplay = true } } }
    /// Domain the letter tile is drawn from.
    public var letterSource = "" { didSet { if letterSource != oldValue { needsDisplay = true } } }
    public var isUnloaded = false { didSet { alphaValue = isUnloaded ? SidebarMetrics.unloadedIconAlpha : 1 } }
    var showsChangedDot = false { didSet { dot.isHidden = !showsChangedDot } }
    var isLoading = false { didSet { if isLoading != oldValue { updateSpinner() } } }

    private let dot = CALayer()
    private let spinner = CAShapeLayer()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Shown, hidden and moved without Core Animation's implicit 0.25 s fade (5.1a):
        // the row adds its own crossfades on the tokens.
        dot.actions = CALayer.noImplicitActions
        spinner.actions = CALayer.noImplicitActions
        dot.isHidden = true
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

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        // Differentiate Without Colour (5.3b): larger, with a ring (`ChangedMark`); the dot's centre stays put.
        let style = ChangedMark.style()
        let size = style.size, centre = CGPoint(x: bounds.maxX - SidebarMetrics.changedDotSize / 2 + 2,
                                                y: bounds.maxY - SidebarMetrics.changedDotSize / 2 + 2)
        dot.frame = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
        dot.cornerRadius = size / 2
        dot.borderWidth = style.outline
        spinner.frame = bounds
        spinner.path = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.backgroundColor = Palette.accent.cgColor
            dot.borderColor = Palette.changedMarkOutline.cgColor
            spinner.strokeColor = NSColor.secondaryLabelColor.cgColor
        }
        guard !isLoading else { return }
        if let image {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        Self.drawLetterTile(letterSource, in: bounds, scale: window?.backingScaleFactor ?? 2)
    }

    static func drawLetterTile(_ domain: String, in rect: NSRect, scale: CGFloat = 2) {
        letterTile(domain, size: rect.size, scale: scale).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                                                                respectFlipped: true, hints: nil)
    }

    /// Letter tiles by letter, colour, size and scale: rendering the glyph on
    /// every draw was a visible share of each scrolled-in row (2.2b profile).
    /// Kept as bitmaps: an image with a drawing handler ran it again on every
    /// draw (the palette's eight rows on a query's first keystroke, 2.6a profile).
    private static var letterTiles: [String: NSImage] = [:]

    private static func letterTile(_ domain: String, size: NSSize, scale: CGFloat) -> NSImage {
        let letter = domain.first.map { String($0).uppercased() } ?? "•"
        let color = Palette.letterTileColor(for: domain)
        let isDark = NSAppearance.currentDrawing().isDark
        let key = "\(letter)|\(color.hash)|\(size.width)x\(size.height)@\(scale)|\(isDark)"
        if let image = letterTiles[key] { return image }
        let image = NSImage(size: size)
        if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * scale)),
                                         pixelsHigh: Int(ceil(size.height * scale)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
           let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            bitmap.size = size
            let appearance = NSAppearance.currentDrawing()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            // The bitmap's context is in pixels: draw in points.
            context.cgContext.scaleBy(x: scale, y: scale)
            appearance.performAsCurrentDrawingAppearance {
                renderLetterTile(letter, color: color, in: NSRect(origin: .zero, size: size))
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
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
        guard isLoading, SidebarMotion.loadingRing.animates else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 0.9
        spin.repeatCount = .infinity
        spinner.add(spin, forKey: "spin")
    }
}
