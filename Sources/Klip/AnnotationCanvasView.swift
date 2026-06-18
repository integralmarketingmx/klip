import AppKit

/// Lienzo del editor: dibuja la captura base y las anotaciones encima. Maneja el dibujo en vivo,
/// el texto in-place (NSTextField temporal — soporta acentos), y para el texto: selección, mover,
/// reeditar y cambiar tamaño. Aplana todo a imagen a resolución completa.
final class AnnotationCanvasView: NSView {
    private let baseImage: NSImage
    private(set) var annotations: [SnapAnnotation] = []
    private var draft: SnapAnnotation?

    // Texto in-place / selección.
    private var activeTextField: NSTextField?
    private var editingID: UUID?              // anotación de texto que se está reeditando
    private var editFontSize: CGFloat = 20
    private var editColor: NSColor = .systemRed
    private(set) var selectedTextID: UUID?    // texto seleccionado (caja resaltada)
    private var movingTextID: UUID?           // texto que se está arrastrando
    private var moveOffset = CGSize.zero

    var currentTool: SnapTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var currentFontSize: CGFloat = 20

    /// Notifica cambios de selección (para que la toolbar refleje el tamaño del texto elegido).
    var onSelectionChange: (() -> Void)?

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
        drawSelectionHighlight()
    }

    private func drawSelectionHighlight() {
        guard let id = selectedTextID,
              let ann = annotations.first(where: { $0.id == id }),
              let box = ann.textBounds()?.insetBy(dx: -4, dy: -4) else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    // MARK: - Ratón

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if currentTool == .text {
            commitActiveText()
            // ¿Click sobre un texto existente? (de arriba hacia abajo)
            if let idx = annotations.lastIndex(where: {
                $0.tool == .text && ($0.textBounds()?.insetBy(dx: -6, dy: -6).contains(p) ?? false)
            }) {
                let ann = annotations[idx]
                if event.clickCount >= 2 {
                    // Doble clic → reeditar.
                    annotations.remove(at: idx)
                    editingID = ann.id
                    selectedTextID = nil
                    beginTextEditing(at: ann.start, existing: ann)
                } else {
                    // Clic simple → seleccionar y preparar arrastre.
                    selectedTextID = ann.id
                    movingTextID = ann.id
                    moveOffset = CGSize(width: p.x - ann.start.x, height: p.y - ann.start.y)
                    onSelectionChange?()
                }
                needsDisplay = true
                return
            }
            // Espacio vacío → nuevo texto.
            selectedTextID = nil
            beginTextEditing(at: p, existing: nil)
            needsDisplay = true
            return
        }

        // Herramientas de dibujo.
        selectedTextID = nil
        commitActiveText()
        draft = SnapAnnotation(tool: currentTool, color: currentColor,
                           lineWidth: currentLineWidth, points: [p], text: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // Mover un texto seleccionado.
        if let movingID = movingTextID, let idx = annotations.firstIndex(where: { $0.id == movingID }) {
            annotations[idx].points = [CGPoint(x: p.x - moveOffset.width, y: p.y - moveOffset.height)]
            needsDisplay = true
            return
        }

        guard var d = draft else { return }
        if d.tool == .pencil || d.tool == .marker {
            d.points.append(p)
        } else {
            d.points = [d.points.first ?? p, p]
        }
        draft = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingTextID != nil { movingTextID = nil; return }
        guard let d = draft else { return }
        if d.points.count > 1 || d.tool == .pencil || d.tool == .marker {
            annotations.append(d)
        }
        draft = nil
        needsDisplay = true
    }

    // MARK: - Texto in-place

    private func beginTextEditing(at point: NSPoint, existing: SnapAnnotation?) {
        let fontSize = existing?.fontSize ?? currentFontSize
        let color = existing?.color ?? currentColor
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let lineHeight = font.ascender - font.descender
        let fieldHeight = max(24, lineHeight + 8)
        // Posiciona el campo de modo que, al confirmar, el texto dibujado caiga en `point`.
        let field = NSTextField(frame: NSRect(x: point.x - 4,
                                              y: point.y - (fieldHeight - lineHeight) / 2,
                                              width: 260, height: fieldHeight))
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = .white.withAlphaComponent(0.92)
        field.font = font
        field.textColor = color
        field.focusRingType = .none
        field.placeholderString = "Escribe…"
        field.stringValue = existing?.text ?? ""
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        editFontSize = fontSize
        editColor = color
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) { commitActiveText() }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let frame = field.frame
        let font = field.font ?? NSFont.systemFont(ofSize: editFontSize, weight: .semibold)
        let id = editingID
        activeTextField = nil
        editingID = nil
        field.removeFromSuperview()
        guard !text.isEmpty else { needsDisplay = true; return }
        let lineHeight = font.ascender - font.descender
        let drawY = frame.minY + (frame.height - lineHeight) / 2
        let origin = CGPoint(x: frame.minX + 4, y: drawY)
        var ann = SnapAnnotation(tool: .text, color: editColor, lineWidth: currentLineWidth,
                             points: [origin], text: text, fontSize: editFontSize)
        if let id { ann.id = id }   // conserva la identidad al reeditar
        annotations.append(ann)
        selectedTextID = ann.id
        onSelectionChange?()
        needsDisplay = true
    }

    // MARK: - Tamaño de fuente

    /// Tamaño efectivo a mostrar en la toolbar: el del texto seleccionado, o el actual.
    var effectiveFontSize: CGFloat {
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) { return a.fontSize }
        return currentFontSize
    }

    /// Aplica un nuevo tamaño: al texto seleccionado (si lo hay) y como tamaño por defecto para el próximo.
    func setFontSize(_ size: CGFloat) {
        let clamped = max(10, min(120, size))
        currentFontSize = clamped
        if let field = activeTextField {
            field.font = NSFont.systemFont(ofSize: clamped, weight: .semibold)
            editFontSize = clamped
        }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].fontSize = clamped
        }
        needsDisplay = true
    }

    func bumpFontSize(_ delta: CGFloat) { setFontSize(effectiveFontSize + delta) }

    /// Fija el color actual y, si hay texto seleccionado o en edición, lo recolorea.
    func setColor(_ color: NSColor) {
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].color = color
        }
        needsDisplay = true
    }

    // MARK: - Acciones

    func undo() {
        if activeTextField != nil { activeTextField?.removeFromSuperview(); activeTextField = nil; editingID = nil; return }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        selectedTextID = nil
        needsDisplay = true
    }

    /// Aplana base + anotaciones a un NSImage a resolución de píxeles completa (Retina).
    func flattened() -> NSImage {
        commitActiveText()
        let savedSelection = selectedTextID
        selectedTextID = nil   // no rasterizar la caja de selección
        defer { selectedTextID = savedSelection }

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
