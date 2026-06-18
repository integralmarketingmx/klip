import AppKit

/// Lienzo del editor: dibuja la captura base y las anotaciones encima. Maneja el dibujo en vivo,
/// el texto in-place (NSTextField temporal — soporta acentos), el undo y el aplanado a imagen.
final class AnnotationCanvasView: NSView {
    private let baseImage: NSImage
    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?
    private var activeTextField: NSTextField?

    var currentTool: SnapTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for a in annotations { a.draw() }
        draft?.draw()
    }

    // MARK: - Ratón / dibujo

    override func mouseDown(with event: NSEvent) {
        commitActiveText()
        let p = convert(event.locationInWindow, from: nil)
        if currentTool == .text {
            beginTextEditing(at: p)
            return
        }
        draft = Annotation(tool: currentTool, color: currentColor,
                           lineWidth: currentLineWidth, points: [p], text: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var d = draft else { return }
        let p = convert(event.locationInWindow, from: nil)
        if d.tool == .pencil || d.tool == .marker {
            d.points.append(p)
        } else {
            d.points = [d.points.first ?? p, p]   // formas: start + actual
        }
        draft = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let d = draft else { return }
        // Descarta trazos/forma de tamaño cero.
        if d.points.count > 1 || d.tool == .pencil || d.tool == .marker {
            annotations.append(d)
        }
        draft = nil
        needsDisplay = true
    }

    // MARK: - Texto in-place

    private func beginTextEditing(at point: NSPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 10, width: 200, height: 24))
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = .white.withAlphaComponent(0.9)
        field.font = NSFont.systemFont(ofSize: max(14, currentLineWidth * 7), weight: .semibold)
        field.textColor = currentColor
        field.focusRingType = .none
        field.placeholderString = "Escribe…"
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) { commitActiveText() }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = field.frame.origin
        activeTextField = nil
        field.removeFromSuperview()
        guard !text.isEmpty else { return }
        annotations.append(Annotation(tool: .text, color: currentColor,
                                      lineWidth: currentLineWidth,
                                      points: [CGPoint(x: origin.x + 2, y: origin.y + 4)], text: text))
        needsDisplay = true
    }

    // MARK: - Acciones

    func undo() {
        if activeTextField != nil { activeTextField?.removeFromSuperview(); activeTextField = nil; return }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    /// Aplana base + anotaciones a un NSImage a resolución de píxeles completa (Retina).
    func flattened() -> NSImage {
        commitActiveText()
        let pxW = baseImage.representations.first?.pixelsWide ?? Int(bounds.width)
        let pxH = baseImage.representations.first?.pixelsHigh ?? Int(bounds.height)
        guard pxW > 0, pxH > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return baseImage }
        rep.size = bounds.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for a in annotations { a.draw() }
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: bounds.size)
        out.addRepresentation(rep)
        return out
    }
}
