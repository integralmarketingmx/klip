import AppKit

/// Lienzo del editor: dibuja la captura base y las anotaciones encima. Maneja el dibujo en vivo,
/// el texto in-place (NSTextField temporal — soporta acentos), y para el texto: selección, mover,
/// reeditar y cambiar tamaño. Aplana todo a imagen a resolución completa.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let baseImage: NSImage
    var annotations: [Annotation] = []        // internal: lo mutan también las acciones de +Klip
    private var draft: Annotation?

    // Texto in-place / selección.
    private var activeTextField: NSTextField?
    private var editingID: UUID?              // anotación de texto que se está reeditando
    private var editFontSize: CGFloat = 20
    private var editColor: NSColor = .systemRed
    var selectedID: UUID?                 // anotación seleccionada (caja resaltada); lo toca también +Klip
    private var movingID: UUID?               // anotación que se está arrastrando (cualquier forma o texto)
    private var lastDragPoint = CGPoint.zero  // último punto del arrastre (para mover por delta)

    // Re-portado del editor anterior (Fase C del merge Snap): historial de rehacer y respaldo del
    // último "Limpiar todo". Son internal para que AnnotationCanvasView+Klip.swift los maneje.
    var redoStack: [Annotation] = []          // para Rehacer (⌘⇧Z)
    var clearedBackup: [Annotation]?          // respaldo del último "Limpiar todo" (deshacer con ⌘Z)

    var currentTool: SnapTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var currentFontSize: CGFloat = 20

    /// Notifica cambios de selección (para que la toolbar refleje el tamaño del texto elegido).
    var onSelectionChange: (() -> Void)?
    /// El menú contextual avisa a la toolbar qué herramienta se eligió (para resaltar el botón).
    var onToolPick: ((SnapTool) -> Void)?

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        // El texto que se está reeditando se oculta del lienzo (lo muestra el NSTextField encima);
        // así un Undo/cancel durante la reedición restaura el original en vez de perderlo.
        for a in annotations where a.id != editingID { a.draw() }
        draft?.draw()
        drawSelectionHighlight()
    }

    private func drawSelectionHighlight() {
        guard let id = selectedID,
              let ann = annotations.first(where: { $0.id == id }),
              let box = ann.selectionBounds()?.insetBy(dx: -2, dy: -2) else { return }
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
                    // Doble clic → reeditar. NO se quita del array: se oculta vía editingID mientras
                    // se edita (draw lo salta), de modo que un Undo/cancel restaure el texto original.
                    editingID = ann.id
                    selectedID = nil
                    beginTextEditing(at: ann.start, existing: ann)
                } else {
                    // Clic simple → seleccionar y preparar arrastre.
                    selectedID = ann.id
                    movingID = ann.id
                    lastDragPoint = p
                    onSelectionChange?()
                }
                needsDisplay = true
                return
            }
            // Espacio vacío → nuevo texto.
            selectedID = nil
            onSelectionChange?()   // sin texto seleccionado, la toolbar refleja el color/tamaño actuales
            beginTextEditing(at: p, existing: nil)
            needsDisplay = true
            return
        }

        // Herramientas de dibujo.
        commitActiveText()
        // ¿Presionaste sobre una anotación existente? → seleccionarla y prepararla para ARRASTRAR (mover),
        // en vez de empezar a dibujar una nueva encima. Sin esto, intentar mover una forma dibujaba otra.
        if let idx = hitAnnotationIndex(at: p) {
            selectedID = annotations[idx].id
            movingID = annotations[idx].id
            lastDragPoint = p
            onSelectionChange?()
            needsDisplay = true
            return
        }
        // Espacio vacío → nueva forma.
        selectedID = nil
        onSelectionChange?()
        draft = Annotation(tool: currentTool, color: currentColor,
                           lineWidth: currentLineWidth, points: [p], text: nil)
    }

    /// Índice de la anotación bajo el punto (cualquier forma o texto), para seleccionar/arrastrar.
    /// Prioriza la selección actual si el punto cae dentro de ella; si no, la de más arriba.
    private func hitAnnotationIndex(at p: CGPoint) -> Int? {
        if let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }),
           annotations[idx].selectionBounds()?.contains(p) ?? false {
            return idx
        }
        return annotations.lastIndex(where: { $0.selectionBounds()?.contains(p) ?? false })
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // Mover la anotación seleccionada (cualquier forma o texto): desplaza TODOS sus puntos por el
        // delta del arrastre, así un rectángulo/flecha/elipse/trazo se mueve sin deformarse.
        if let id = movingID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            let dx = p.x - lastDragPoint.x, dy = p.y - lastDragPoint.y
            annotations[idx].points = annotations[idx].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            lastDragPoint = p
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
        if movingID != nil { movingID = nil; needsDisplay = true; return }
        guard let d = draft else { return }
        // Solo se añade si hubo arrastre real (2+ puntos). Un clic suelto con lápiz/marcador NO crea un
        // trazo de 1 punto invisible (que ensuciaría annotations/undo y dejaría una selección vacía).
        if d.points.count > 1 {
            annotations.append(d)
            redoStack.removeAll(); clearedBackup = nil   // una acción nueva invalida rehacer/limpiar
            selectedID = d.id            // auto-seleccionar la forma recién dibujada (para recolorear/mover)
            onSelectionChange?()
        } else {
            // Clic sin arrastre con una herramienta de dibujo: seleccionar la forma existente bajo el
            // cursor (la de más arriba). Así puedes picar un rectángulo ya hecho y cambiarle el color
            // sin volver a dibujarlo. Click en vacío → deseleccionar.
            let p = d.points.first ?? .zero
            if let idx = annotations.lastIndex(where: { $0.selectionBounds()?.contains(p) ?? false }) {
                selectedID = annotations[idx].id
            } else {
                selectedID = nil
            }
            onSelectionChange?()
        }
        draft = nil
        needsDisplay = true
    }

    // MARK: - Texto in-place

    private func beginTextEditing(at point: NSPoint, existing: Annotation?) {
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
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        editFontSize = fontSize
        editColor = color
        growTextField()   // ajustar el ancho al contenido inicial (al reeditar un texto existente)
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) { commitActiveText() }

    /// El campo de texto es de una sola línea: lo hacemos crecer en ancho conforme se escribe para que
    /// el texto completo (desde el inicio) quede siempre visible, sin "navegar" dentro del campo.
    func controlTextDidChange(_ obj: Notification) { growTextField() }

    private func growTextField() {
        guard let field = activeTextField else { return }
        let font = field.font ?? NSFont.systemFont(ofSize: editFontSize, weight: .semibold)
        let shown = field.stringValue.isEmpty ? (field.placeholderString ?? "") : field.stringValue
        let textW = (shown as NSString).size(withAttributes: [.font: font]).width
        let pad: CGFloat = 8
        // Ancho deseado, sin exceder el ancho total del lienzo.
        let desired = min(max(120, textW + 28), max(120, bounds.width - pad * 2))
        var f = field.frame
        // Si se saldría por la derecha (p.ej. el texto empezó cerca del borde), recolocar a la izquierda.
        if f.minX + desired > bounds.width - pad {
            f.origin.x = max(pad, bounds.width - pad - desired)
        }
        f.size.width = desired
        field.frame = f
    }

    func commitActiveText() {   // internal: lo invoca también AnnotationCanvasView+Klip (clearAll)
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let frame = field.frame
        let font = field.font ?? NSFont.systemFont(ofSize: editFontSize, weight: .semibold)
        let id = editingID
        activeTextField = nil
        editingID = nil
        field.removeFromSuperview()
        // Si se reeditaba un texto, quitar el original: lo reemplazamos abajo, o (si quedó vacío)
        // lo eliminamos confirmando vacío.
        if let id { annotations.removeAll { $0.id == id } }
        guard !text.isEmpty else { needsDisplay = true; return }
        let lineHeight = font.ascender - font.descender
        let drawY = frame.minY + (frame.height - lineHeight) / 2
        let origin = CGPoint(x: frame.minX + 4, y: drawY)
        var ann = Annotation(tool: .text, color: editColor, lineWidth: currentLineWidth,
                             points: [origin], text: text, fontSize: editFontSize)
        if let id { ann.id = id }   // conserva la identidad al reeditar
        annotations.append(ann)
        redoStack.removeAll(); clearedBackup = nil   // una acción nueva invalida rehacer/limpiar
        selectedID = ann.id
        onSelectionChange?()
        needsDisplay = true
    }

    // MARK: - Tamaño de fuente

    /// Tamaño efectivo a mostrar en la toolbar: el del texto seleccionado, o el actual.
    var effectiveFontSize: CGFloat {
        if let id = selectedID, let a = annotations.first(where: { $0.id == id }) { return a.fontSize }
        return currentFontSize
    }

    /// Color efectivo a reflejar en la toolbar: el del texto seleccionado, o el actual.
    var effectiveColor: NSColor {
        if let id = selectedID, let a = annotations.first(where: { $0.id == id }) { return a.color }
        return currentColor
    }

    /// Aplica un nuevo tamaño: al texto seleccionado (si lo hay) y como tamaño por defecto para el próximo.
    func setFontSize(_ size: CGFloat) {
        let clamped = max(10, min(120, size))
        currentFontSize = clamped
        if let field = activeTextField {
            field.font = NSFont.systemFont(ofSize: clamped, weight: .semibold)
            editFontSize = clamped
        }
        if let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].fontSize = clamped
        }
        needsDisplay = true
    }

    func bumpFontSize(_ delta: CGFloat) { setFontSize(effectiveFontSize + delta) }

    /// Fija el color actual y, si hay texto seleccionado o en edición, lo recolorea.
    func setColor(_ color: NSColor) {
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        if let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].color = color
        }
        needsDisplay = true
    }

    // MARK: - Acciones

    func undo() {
        // Si se está editando texto, cancelar la edición: el original sigue en el array (oculto por
        // editingID) y reaparece al limpiar editingID. No se pierde el texto reeditado.
        if activeTextField != nil {
            activeTextField?.removeFromSuperview(); activeTextField = nil; editingID = nil
            needsDisplay = true
            return
        }
        // Deshacer un "Limpiar todo": si lo último fue limpiar (lienzo vacío con respaldo), lo restaura
        // entero antes de seguir deshaciendo anotaciones sueltas.
        if annotations.isEmpty, let backup = clearedBackup {
            annotations = backup
            clearedBackup = nil
            selectedID = nil
            needsDisplay = true
            return
        }
        guard !annotations.isEmpty else { return }
        redoStack.append(annotations.removeLast())   // permite rehacer (⌘⇧Z)
        selectedID = nil
        needsDisplay = true
    }

    /// Aplana base + anotaciones a un NSImage a resolución de píxeles completa (Retina).
    func flattened() -> NSImage {
        commitActiveText()
        let savedSelection = selectedID
        selectedID = nil   // no rasterizar la caja de selección
        defer { selectedID = savedSelection }

        // Color space de la captura base. Las capturas de macOS en pantallas wide-gamut vienen en
        // Display P3; rasterizar en `.deviceRGB` (sin gestión de color) las exporta lavadas/blanquiscas
        // en el navegador. Rasterizamos en el MISMO color space de la base para preservar su perfil ICC.
        let baseCG = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let pxW = baseCG?.width ?? baseImage.representations.first?.pixelsWide ?? Int(bounds.width)
        let pxH = baseCG?.height ?? baseImage.representations.first?.pixelsHigh ?? Int(bounds.height)
        let colorSpace = baseCG?.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        if pxW > 0, pxH > 0, let colorSpace,
           let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                               bytesPerRow: 0, space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            // El contexto está en píxeles físicos; escalar para dibujar en coordenadas de "puntos" (bounds).
            ctx.scaleBy(x: CGFloat(pxW) / bounds.width, y: CGFloat(pxH) / bounds.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            for a in annotations { a.draw() }
            NSGraphicsContext.restoreGraphicsState()
            if let outCG = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: outCG)
                rep.size = bounds.size
                let out = NSImage(size: bounds.size)
                out.addRepresentation(rep)
                return out
            }
        }

        // Fallback (no se pudo crear el bitmap a resolución de píxeles): rasterizar a tamaño de puntos
        // PERO incluyendo las anotaciones. Nunca devolver la base limpia: perdería el trabajo del usuario.
        let out = NSImage(size: bounds.size)
        out.lockFocus()
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for a in annotations { a.draw() }
        out.unlockFocus()
        return out
    }
}
