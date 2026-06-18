import AppKit

/// Ventana sin borde a pantalla completa que muestra la captura congelada y atenuada, y deja
/// al usuario arrastrar una región. Al soltar, recorta y entrega un NSImage de la zona elegida.
final class CaptureOverlayController {
    private var window: NSWindow?
    private let shot: DisplayShot
    private let onComplete: (NSImage?) -> Void

    init(shot: DisplayShot, onComplete: @escaping (NSImage?) -> Void) {
        self.shot = shot
        self.onComplete = onComplete
    }

    func present() {
        let frame = shot.screen.frame
        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.ignoresMouseEvents = false
        win.hasShadow = false

        let view = CaptureOverlayView(shot: shot) { [weak self] rectInView in
            self?.finish(selectionInView: rectInView)
        } onCancel: { [weak self] in
            self?.dismiss(nil)
        }
        win.contentView = view
        win.setFrame(frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(view)
        self.window = win
    }

    /// Convierte la selección (puntos, origen abajo-izquierda de la vista) a píxeles del bitmap
    /// (origen arriba-izquierda) y recorta el CGImage.
    private func finish(selectionInView rect: NSRect) {
        guard rect.width >= 4, rect.height >= 4 else { dismiss(nil); return }
        let scale = shot.scale
        let viewH = shot.screen.frame.height
        let imgBounds = CGRect(x: 0, y: 0, width: shot.cgImage.width, height: shot.cgImage.height)
        let px = CGRect(
            x: rect.minX * scale,
            y: (viewH - rect.maxY) * scale,        // flip Y: Cocoa (abajo) → CGImage (arriba)
            width: rect.width * scale,
            height: rect.height * scale
        ).integral.intersection(imgBounds)         // clamp: selección al borde no debe exceder el bitmap

        guard !px.isNull, px.width >= 1, px.height >= 1,
              let cropped = shot.cgImage.cropping(to: px) else { dismiss(nil); return }
        let image = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        dismiss(image)
    }

    private func dismiss(_ image: NSImage?) {
        window?.orderOut(nil)
        window = nil
        onComplete(image)
    }
}

/// Vista que dibuja la captura congelada, la atenuación, la selección y el badge de dimensiones.
private final class CaptureOverlayView: NSView {
    private let shot: DisplayShot
    private let onSelect: (NSRect) -> Void
    private let onCancel: () -> Void

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private let bgImage: NSImage

    init(shot: DisplayShot, onSelect: @escaping (NSRect) -> Void, onCancel: @escaping () -> Void) {
        self.shot = shot
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.bgImage = NSImage(cgImage: shot.cgImage,
                               size: NSSize(width: shot.screen.frame.width, height: shot.screen.frame.height))
        super.init(frame: NSRect(origin: .zero, size: shot.screen.frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        // Fondo: la captura congelada.
        bgImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        // Atenuación general.
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        guard currentRect.width > 0, currentRect.height > 0 else { return }

        // "Agujero": vuelve a pintar la zona seleccionada sin atenuar.
        bgImage.draw(in: currentRect, from: pixelSourceRect(for: currentRect), operation: .copy, fraction: 1)

        // Borde de la selección.
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: currentRect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1.5
        border.stroke()

        drawDimensionBadge(for: currentRect)
    }

    /// Rect fuente (en puntos de la imagen, origen abajo-izquierda) correspondiente a la zona de la vista.
    private func pixelSourceRect(for rect: NSRect) -> NSRect { rect }

    private func drawDimensionBadge(for rect: NSRect) {
        let wPx = Int(rect.width * shot.scale)
        let hPx = Int(rect.height * shot.scale)
        let label = "\(wPx) × \(hPx)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        var badge = NSRect(x: rect.minX, y: rect.maxY + 6,
                           width: textSize.width + pad * 2, height: textSize.height + pad)
        // Si no cabe arriba, colócalo dentro/abajo.
        if badge.maxY > bounds.maxY { badge.origin.y = rect.minY - badge.height - 6 }
        if badge.minY < bounds.minY { badge.origin.y = rect.minY + 6 }
        badge.origin.x = min(badge.origin.x, bounds.maxX - badge.width)

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(at: NSPoint(x: badge.minX + pad, y: badge.minY + pad / 2), withAttributes: attrs)
    }

    // MARK: - Ratón

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y),
                             width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = currentRect
        startPoint = nil
        if rect.width >= 4, rect.height >= 4 { onSelect(rect) } else { onCancel() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() }   // Esc
        else { super.keyDown(with: event) }
    }
}
