import SwiftUI
import AppKit

/// Herramienta de anotación activa.
enum AnnoTool: String, CaseIterable, Identifiable {
    case arrow, line, rect, ellipse, highlight, pen, text
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .arrow: "arrow.up.left"; case .line: "line.diagonal"; case .rect: "rectangle"
        case .ellipse: "circle"; case .highlight: "highlighter"; case .pen: "scribble"
        case .text: "textformat"
        }
    }
    var help: String {
        switch self {
        case .arrow: "Flecha"; case .line: "Línea"; case .rect: "Recuadro"
        case .ellipse: "Elipse"; case .highlight: "Resaltar"; case .pen: "Lápiz"
        case .text: "Texto"
        }
    }
}

/// Un trazo de anotación sobre la imagen.
struct Annotation {
    var id = UUID()
    var tool: AnnoTool
    var color: NSColor
    var width: CGFloat
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []   // lápiz
    var text: String = ""        // texto
    var fontSize: CGFloat = 24   // solo texto

    var font: NSFont { .boldSystemFont(ofSize: fontSize) }

    /// Rectángulo que ocupa el texto (para selección / hit-testing / mover). nil si no es texto.
    func textBounds() -> CGRect? {
        guard tool == .text, !text.isEmpty else { return nil }
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGRect(origin: start, size: size)
    }
}

/// Vista AppKit que dibuja la imagen base + las anotaciones y captura el ratón según la herramienta.
/// El texto es editable (doble clic), movible (arrastre) y redimensionable (A−/A+).
final class AnnotationCanvasNSView: NSView {
    let image: NSImage
    var annotations: [Annotation] = []
    var tool: AnnoTool = .arrow
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var currentFontSize: CGFloat = 24
    private var draft: Annotation?

    // Texto in-place / selección.
    private var activeTextField: NSTextField?
    private var editingID: UUID?
    private var editFontSize: CGFloat = 24
    private var editColor: NSColor = .systemRed
    private(set) var selectedTextID: UUID?
    private var movingTextID: UUID?
    private var moveOffset = CGSize.zero
    private var redoStack: [Annotation] = []     // para Rehacer (⌘⇧Z)
    private var clearedBackup: [Annotation]?     // respaldo del último "Limpiar todo" para poder deshacerlo (⌘Z)
    var onToolPick: ((AnnoTool) -> Void)?        // el menú contextual avisa a SwiftUI qué herramienta eligió

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError("no soportado") }

    override var isFlipped: Bool { true }   // origen arriba-izquierda (como una captura)
    override var intrinsicContentSize: NSSize { image.size }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        for a in annotations { render(a) }
        if let d = draft { render(d) }
        drawSelectionHighlight()
    }

    private func drawSelectionHighlight() {
        guard let id = selectedTextID,
              let a = annotations.first(where: { $0.id == id }),
              let box = a.textBounds()?.insetBy(dx: -4, dy: -4) else { return }
        NSColor.controlAccentColor.setStroke()
        let p = NSBezierPath(rect: box)
        p.lineWidth = 1
        p.setLineDash([4, 3], count: 2, phase: 0)
        p.stroke()
    }

    private func render(_ a: Annotation) {
        let path = NSBezierPath()
        path.lineWidth = a.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch a.tool {
        case .rect:
            a.color.setStroke(); path.appendRect(rectOf(a.start, a.end)); path.stroke()
        case .ellipse:
            a.color.setStroke(); path.appendOval(in: rectOf(a.start, a.end)); path.stroke()
        case .line:
            a.color.setStroke(); path.move(to: a.start); path.line(to: a.end); path.stroke()
        case .highlight:
            a.color.withAlphaComponent(0.32).setFill()
            NSBezierPath(rect: rectOf(a.start, a.end)).fill()
        case .pen:
            guard let first = a.points.first else { break }
            a.color.setStroke()
            path.move(to: first)
            for p in a.points.dropFirst() { path.line(to: p) }
            path.stroke()
        case .arrow:
            a.color.setStroke()
            path.move(to: a.start); path.line(to: a.end); path.stroke()
            drawArrowHead(from: a.start, to: a.end, color: a.color, width: a.width)
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [.font: a.font, .foregroundColor: a.color]
            (a.text as NSString).draw(at: a.start, withAttributes: attrs)
        }
    }

    private func rectOf(_ p1: CGPoint, _ p2: CGPoint) -> NSRect {
        NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    private func drawArrowHead(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let len = max(12, width * 3.2)
        let spread = CGFloat.pi / 7
        let p1 = CGPoint(x: to.x - len * cos(angle - spread), y: to.y - len * sin(angle - spread))
        let p2 = CGPoint(x: to.x - len * cos(angle + spread), y: to.y - len * sin(angle + spread))
        let head = NSBezierPath()
        head.move(to: to); head.line(to: p1); head.line(to: p2); head.close()
        color.setFill(); head.fill()
    }

    // MARK: - Ratón

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)   // recupera el foco del teclado (flechas, ⌫) tras tocar la barra

        if tool == .text {
            commitActiveText()
            // ¿Click sobre un texto existente? (de arriba hacia abajo)
            if let idx = annotations.lastIndex(where: {
                $0.tool == .text && ($0.textBounds()?.insetBy(dx: -6, dy: -6).contains(p) ?? false)
            }) {
                let ann = annotations[idx]
                if event.clickCount >= 2 {
                    annotations.remove(at: idx)        // doble clic → reeditar
                    editingID = ann.id
                    selectedTextID = nil
                    beginTextEditing(at: ann.start, existing: ann)
                } else {
                    selectedTextID = ann.id            // clic simple → seleccionar + preparar arrastre
                    movingTextID = ann.id
                    moveOffset = CGSize(width: p.x - ann.start.x, height: p.y - ann.start.y)
                }
                needsDisplay = true
                return
            }
            selectedTextID = nil
            beginTextEditing(at: p, existing: nil)     // espacio vacío → nuevo texto
            needsDisplay = true
            return
        }

        selectedTextID = nil
        commitActiveText()
        var a = Annotation(tool: tool, color: color, width: lineWidth, start: p, end: p)
        if tool == .pen { a.points = [p] }
        draft = a
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if let id = movingTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            let newStart = CGPoint(x: p.x - moveOffset.width, y: p.y - moveOffset.height)
            annotations[idx].start = newStart
            annotations[idx].end = newStart
            needsDisplay = true
            return
        }

        guard var d = draft else { return }
        d.end = p
        if d.tool == .pen { d.points.append(p) }
        draft = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingTextID != nil { movingTextID = nil; return }
        guard let d = draft else { return }
        if d.tool == .pen || hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 3 {
            annotations.append(d)
            redoStack.removeAll()   // una acción nueva invalida el historial de rehacer
            clearedBackup = nil     // …y también el respaldo de "Limpiar todo"
        }
        draft = nil
        needsDisplay = true
    }

    // MARK: - Teclado (flechas mueven la selección, ⌫ la borra)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Mientras se edita texto, el NSTextField es first responder, así que esto no interfiere.
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117:   // ⌫ borrar / supr
            if selectedTextID != nil { deleteSelection(); return }
        case 123: if selectedTextID != nil { moveSelection(dx: -step, dy: 0); return }  // ←
        case 124: if selectedTextID != nil { moveSelection(dx:  step, dy: 0); return }  // →
        case 125: if selectedTextID != nil { moveSelection(dx: 0, dy:  step); return }  // ↓ (vista flipped)
        case 126: if selectedTextID != nil { moveSelection(dx: 0, dy: -step); return }  // ↑
        default: break
        }
        super.keyDown(with: event)
    }

    // MARK: - Menú contextual (clic derecho)

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = menu.addItem(withTitle: "Copiar", action: #selector(ctxCopy), keyEquivalent: "c")
        let undoIt = menu.addItem(withTitle: "Deshacer", action: #selector(ctxUndo), keyEquivalent: "z")
        let redoIt = menu.addItem(withTitle: "Rehacer", action: #selector(ctxRedo), keyEquivalent: "Z")
        redoIt.isEnabled = !redoStack.isEmpty
        undoIt.isEnabled = !annotations.isEmpty || activeTextField != nil || clearedBackup != nil
        if selectedTextID != nil {
            menu.addItem(withTitle: "Borrar selección", action: #selector(ctxDelete), keyEquivalent: "\u{8}")
        }
        menu.addItem(.separator())
        let toolsItem = menu.addItem(withTitle: "Herramienta", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for t in AnnoTool.allCases {
            let it = sub.addItem(withTitle: t.help, action: #selector(ctxTool(_:)), keyEquivalent: "")
            it.representedObject = t.rawValue
            it.target = self
            it.state = (t == tool) ? .on : .off
        }
        toolsItem.submenu = sub
        menu.addItem(.separator())
        menu.addItem(withTitle: "Limpiar todo", action: #selector(ctxClear), keyEquivalent: "")
        for item in menu.items where item.action != nil { item.target = self }
        _ = copy
        return menu
    }

    @objc private func ctxCopy()  { copyToPasteboard() }
    @objc private func ctxUndo()  { undo() }
    @objc private func ctxRedo()  { redo() }
    @objc private func ctxDelete(){ deleteSelection() }
    @objc private func ctxClear() { clearAll() }
    @objc private func ctxTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = AnnoTool(rawValue: raw) else { return }
        tool = t
        onToolPick?(t)
    }

    func copyToPasteboard() {
        guard let img = flattened() else { return }
        let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([img])
    }

    // MARK: - Texto in-place (editable / movible / redimensionable)

    private func beginTextEditing(at point: CGPoint, existing: Annotation?) {
        let fontSize = existing?.fontSize ?? currentFontSize
        let col = existing?.color ?? color
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let h = max(24, font.ascender - font.descender + 8)
        // Vista flipped: frame.origin es arriba-izquierda, igual que draw(at:) del texto.
        let field = NSTextField(frame: NSRect(x: point.x - 4, y: point.y - 4, width: 280, height: h))
        field.font = font
        field.textColor = col
        field.stringValue = existing?.text ?? ""
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = .white.withAlphaComponent(0.92)
        field.focusRingType = .none
        field.placeholderString = "Escribe…"
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        editFontSize = fontSize
        editColor = col
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) { commitActiveText() }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = CGPoint(x: field.frame.minX + 4, y: field.frame.minY + 4)
        let id = editingID
        activeTextField = nil
        editingID = nil
        field.removeFromSuperview()
        guard !text.isEmpty else { needsDisplay = true; return }
        var a = Annotation(tool: .text, color: editColor, width: lineWidth,
                           start: origin, end: origin, text: text, fontSize: editFontSize)
        if let id { a.id = id }   // conserva identidad al reeditar
        annotations.append(a)
        redoStack.removeAll()
        clearedBackup = nil
        selectedTextID = a.id
        needsDisplay = true
    }

    // MARK: - Deshacer / rehacer / borrar / mover selección

    func redo() {
        guard !redoStack.isEmpty else { return }
        annotations.append(redoStack.removeLast())
        needsDisplay = true
    }

    func deleteSelection() {
        guard let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        redoStack.append(annotations.remove(at: idx))
        selectedTextID = nil
        needsDisplay = true
    }

    func moveSelection(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].start.x += dx
        annotations[idx].start.y += dy
        annotations[idx].end = annotations[idx].start
        needsDisplay = true
    }

    /// Esc: si se está editando texto, cancela la edición y devuelve true (no cerrar el editor todavía).
    @discardableResult
    func cancelEditingIfActive() -> Bool {
        guard activeTextField != nil else { return false }
        activeTextField?.removeFromSuperview(); activeTextField = nil; editingID = nil
        return true
    }

    // MARK: - Tamaño y color

    var effectiveFontSize: CGFloat {
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) { return a.fontSize }
        return currentFontSize
    }

    func setFontSize(_ size: CGFloat) {
        let clamped = max(10, min(120, size))
        currentFontSize = clamped
        if let field = activeTextField {
            field.font = .boldSystemFont(ofSize: clamped)
            editFontSize = clamped
        }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].fontSize = clamped
        }
        needsDisplay = true
    }

    func bumpFontSize(_ delta: CGFloat) { setFontSize(effectiveFontSize + delta) }

    /// Recolorea el texto seleccionado o en edición (lo invoca la paleta de SwiftUI).
    func setColorForSelection(_ c: NSColor) {
        if let field = activeTextField { field.textColor = c; editColor = c }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].color = c
            needsDisplay = true
        }
    }

    func addText(_ s: String, at p: CGPoint) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        annotations.append(Annotation(tool: .text, color: color, width: lineWidth,
                                      start: p, end: p, text: t, fontSize: currentFontSize))
        needsDisplay = true
    }

    func undo() {
        if activeTextField != nil {
            activeTextField?.removeFromSuperview(); activeTextField = nil; editingID = nil; return
        }
        // Deshacer un "Limpiar todo": si lo último fue limpiar (lienzo vacío con respaldo), lo restaura entero.
        if annotations.isEmpty, let backup = clearedBackup {
            annotations = backup
            clearedBackup = nil
            selectedTextID = nil; needsDisplay = true
            return
        }
        if !annotations.isEmpty {
            redoStack.append(annotations.removeLast())
            selectedTextID = nil; needsDisplay = true
        }
    }
    func clearAll() {
        activeTextField?.removeFromSuperview(); activeTextField = nil
        clearedBackup = annotations.isEmpty ? nil : annotations   // respaldo para poder deshacer (⌘Z)
        redoStack.removeAll()
        annotations.removeAll(); selectedTextID = nil; needsDisplay = true
    }

    /// Aplana imagen + anotaciones a la resolución REAL de la captura (sus píxeles físicos).
    func flattened() -> NSImage? {
        commitActiveText()
        let savedSelection = selectedTextID
        selectedTextID = nil   // no rasterizar la caja de selección
        defer { selectedTextID = savedSelection }

        let pointSize = bounds.size
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }
        let px = image.pixelDimensions
        let pxW = max(1, Int(px.width.rounded()))
        let pxH = max(1, Int(px.height.rounded()))

        let logical = NSImage(size: pointSize, flipped: true) { [weak self] rect in
            guard let self else { return false }
            self.image.draw(in: rect)
            for a in self.annotations { self.render(a) }
            return true
        }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = pointSize
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        logical.draw(in: NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: pointSize)
        out.addRepresentation(rep)
        return out
    }

    func flattenedPNG() -> Data? {
        guard let img = flattened(),
              let rep = img.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Puente para llamar al canvas desde SwiftUI (deshacer, limpiar, exportar, texto, tamaño).
final class CanvasHandle: ObservableObject {
    weak var view: AnnotationCanvasNSView?
}

struct AnnotationCanvas: NSViewRepresentable {
    let image: NSImage
    @Binding var tool: AnnoTool
    @Binding var color: Color
    let handle: CanvasHandle

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let v = AnnotationCanvasNSView(image: image)
        handle.view = v
        return v
    }
    func updateNSView(_ v: AnnotationCanvasNSView, context: Context) {
        v.tool = tool
        v.color = NSColor(color)
        let toolBinding = $tool
        v.onToolPick = { t in toolBinding.wrappedValue = t }   // menú contextual → estado de SwiftUI
    }
}

/// Editor de anotación: barra de herramientas + lienzo + acciones (copiar / guardar / añadir a Klip).
struct AnnotationView: View {
    let image: NSImage
    /// Tamaño con el que se MUESTRA el lienzo (la captura se escala para caber en pantalla — zoom out).
    /// Si es nil, se usa el tamaño nativo de la imagen.
    var displaySize: CGSize? = nil
    var onAddToKlip: (NSImage) -> Void
    var onClose: () -> Void

    @StateObject private var handle = CanvasHandle()
    @State private var tool: AnnoTool = .arrow
    @State private var color: Color = .red

    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]

    private var canvasSize: CGSize { displaySize ?? image.size }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Lienzo escalado para caber completo: sin scroll, la barra no tapa contenido.
            AnnotationCanvas(image: image, tool: $tool, color: $color, handle: handle)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        // Atajos de teclado del editor (botones ocultos: no saturan la barra).
        .background {
            Button("") { copy() }.keyboardShortcut("c", modifiers: .command).hidden()
            Button("") { handle.view?.undo() }.keyboardShortcut("z", modifiers: .command).hidden()
            Button("") { handle.view?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).hidden()
            Button("") { save() }.keyboardShortcut("s", modifiers: .command).hidden()
            // Esc: primero cancela la edición de texto en curso; si no hay, cierra el editor.
            Button("") { if handle.view?.cancelEditingIfActive() != true { onClose() } }
                .keyboardShortcut(.cancelAction).hidden()
            // ⌘W cerrar (al final para que Esc tenga su propia ruta).
            Button("") { onClose() }.keyboardShortcut("w", modifiers: .command).hidden()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(AnnoTool.allCases) { t in
                Button { tool = t } label: { Image(systemName: t.symbol) }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tool == t ? Color.accentColor.opacity(0.25) : .clear))
                    .help(t.help)
            }
            Divider().frame(height: 20)
            ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                Button { color = c; handle.view?.setColorForSelection(NSColor(c)) } label: {
                    Circle().fill(c).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(c == color ? 0.9 : 0.2), lineWidth: c == color ? 2 : 1))
                }.buttonStyle(.plain)
            }
            Divider().frame(height: 20)
            // Tamaño de texto (afecta al seleccionado o al próximo).
            Button { handle.view?.bumpFontSize(-4) } label: { Image(systemName: "textformat.size.smaller") }
                .buttonStyle(.borderless).help("Texto más chico")
            Button { handle.view?.bumpFontSize(4) } label: { Image(systemName: "textformat.size.larger") }
                .buttonStyle(.borderless).help("Texto más grande")
            Spacer()
            Button { handle.view?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless).help("Deshacer")
            Button { handle.view?.clearAll() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Limpiar")
            Divider().frame(height: 20)
            Button { copy() } label: { Label("Copiar", systemImage: "doc.on.doc") }
                .help("Copiar al portapapeles (⌘C)")
            Button { save() } label: { Label("Guardar", systemImage: "square.and.arrow.down") }
            Button { addToKlip() } label: { Label("Copiar y añadir a Klip", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .help("Copia al portapapeles y guarda en el historial de Klip")
        }
        .padding(10)
    }

    private func copy() {
        guard let img = handle.view?.flattened() else { return }
        let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([img])
    }
    private func save() {
        guard let png = handle.view?.flattenedPNG() else { return }
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.png]
        sp.nameFieldStringValue = "klip-anotacion.png"
        sp.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        // Manejo del resultado: al guardar OK, abrir la carpeta con el archivo seleccionado y cerrar el
        // editor (guardar es una acción terminal). Si se cancela o falla, el editor se queda visible.
        let handleResult: (NSApplication.ModalResponse) -> Void = { resp in
            guard resp == .OK, let url = sp.url else { return }   // cancelado: no cerrar
            do {
                try png.write(to: url, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([url])   // abre la carpeta y selecciona el PNG
                onClose()
            } catch { NSSound.beep() }                                  // error real: avisar, no cerrar
        }
        // Como hoja del editor para que el nivel .floating de la ventana no tape el panel de guardado.
        if let win = handle.view?.window { sp.beginSheetModal(for: win, completionHandler: handleResult) }
        else { sp.begin(completionHandler: handleResult) }
    }
    private func addToKlip() {
        guard let img = handle.view?.flattened() else { return }
        let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([img])   // copia además de guardar
        onAddToKlip(img)
        onClose()
    }
}
