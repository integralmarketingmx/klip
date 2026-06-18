import SwiftUI
import AppKit

/// Herramienta de anotación activa.
enum AnnoTool: String, CaseIterable, Identifiable {
    case arrow, rect, highlight, pen, text
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .arrow: "arrow.up.left"; case .rect: "rectangle"; case .highlight: "highlighter"
        case .pen: "scribble"; case .text: "textformat"
        }
    }
    var help: String {
        switch self {
        case .arrow: "Flecha"; case .rect: "Recuadro"; case .highlight: "Resaltar"
        case .pen: "Lápiz"; case .text: "Texto"
        }
    }
}

/// Un trazo de anotación sobre la imagen.
struct Annotation {
    var tool: AnnoTool
    var color: NSColor
    var width: CGFloat
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []   // lápiz
    var text: String = ""        // texto
}

/// Vista AppKit que dibuja la imagen base + las anotaciones y captura el ratón según la herramienta.
final class AnnotationCanvasNSView: NSView {
    let image: NSImage
    var annotations: [Annotation] = []
    var tool: AnnoTool = .arrow
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    private var draft: Annotation?
    /// El canvas pide a SwiftUI que muestre un campo para escribir el texto en ese punto.
    var onRequestText: ((CGPoint) -> Void)?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError("no soportado") }

    override var isFlipped: Bool { true }   // origen arriba-izquierda (como una captura)
    override var intrinsicContentSize: NSSize { image.size }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        for a in annotations { render(a) }
        if let d = draft { render(d) }
    }

    private func render(_ a: Annotation) {
        let path = NSBezierPath()
        path.lineWidth = a.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch a.tool {
        case .rect:
            a.color.setStroke()
            path.appendRect(rectOf(a.start, a.end))
            path.stroke()
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
            path.move(to: a.start); path.line(to: a.end)
            path.stroke()
            drawArrowHead(from: a.start, to: a.end, color: a.color, width: a.width)
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: max(14, a.width * 5)),
                .foregroundColor: a.color]
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

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if tool == .text { onRequestText?(p); return }
        var a = Annotation(tool: tool, color: color, width: lineWidth, start: p, end: p)
        if tool == .pen { a.points = [p] }
        draft = a
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard var d = draft else { return }
        let p = convert(event.locationInWindow, from: nil)
        d.end = p
        if d.tool == .pen { d.points.append(p) }
        draft = d
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let d = draft else { return }
        // descartar trazos accidentales de tamaño nulo (salvo lápiz)
        if d.tool == .pen || hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 3 {
            annotations.append(d)
        }
        draft = nil
        needsDisplay = true
    }

    func addText(_ s: String, at p: CGPoint) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        annotations.append(Annotation(tool: .text, color: color, width: lineWidth, start: p, end: p, text: t))
        needsDisplay = true
    }
    func undo() { if !annotations.isEmpty { annotations.removeLast(); needsDisplay = true } }
    func clearAll() { annotations.removeAll(); needsDisplay = true }

    /// Aplana imagen + anotaciones a la resolución REAL de la captura (sus píxeles físicos), no a la
    /// escala de la pantalla donde quede la ventana. Antes se usaba cacheDisplay, que degradaba la
    /// captura a la mitad de resolución si la ventana caía en un monitor 1x y resampleaba siempre.
    func flattened() -> NSImage? {
        let pointSize = bounds.size
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }
        let px = image.pixelDimensions            // píxeles físicos de la captura original
        let pxW = max(1, Int(px.width.rounded()))
        let pxH = max(1, Int(px.height.rounded()))

        // Imagen lógica (en puntos) con orientación top-left, igual que el NSView (isFlipped=true).
        let logical = NSImage(size: pointSize, flipped: true) { [weak self] rect in
            guard let self else { return false }
            self.image.draw(in: rect)
            for a in self.annotations { self.render(a) }
            return true
        }
        // Rasterizar esa imagen a un rep del tamaño en píxeles reales (el handler se reejecuta a esa escala).
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

    /// PNG de la imagen aplanada, codificado directo del rep (sin round-trip por TIFF).
    func flattenedPNG() -> Data? {
        guard let img = flattened(),
              let rep = img.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Puente para llamar al canvas desde SwiftUI (deshacer, limpiar, exportar, texto).
final class CanvasHandle: ObservableObject {
    weak var view: AnnotationCanvasNSView?
}

struct AnnotationCanvas: NSViewRepresentable {
    let image: NSImage
    @Binding var tool: AnnoTool
    @Binding var color: Color
    let handle: CanvasHandle
    let onRequestText: (CGPoint) -> Void

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let v = AnnotationCanvasNSView(image: image)
        v.onRequestText = onRequestText
        handle.view = v
        return v
    }
    func updateNSView(_ v: AnnotationCanvasNSView, context: Context) {
        v.tool = tool
        v.color = NSColor(color)
        v.onRequestText = onRequestText
    }
}

/// Editor de anotación: barra de herramientas + lienzo + acciones (copiar / guardar / añadir a Klip).
struct AnnotationView: View {
    let image: NSImage
    var onAddToKlip: (NSImage) -> Void
    var onClose: () -> Void

    @StateObject private var handle = CanvasHandle()
    @State private var tool: AnnoTool = .arrow
    @State private var color: Color = .red
    @State private var askingText = false
    @State private var draftText = ""
    @State private var textPoint: CGPoint = .zero

    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvas(image: image, tool: $tool, color: $color, handle: handle) { p in
                    textPoint = p; draftText = ""; askingText = true
                }
                .frame(width: image.size.width, height: image.size.height)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 520, minHeight: 420)
        .alert("Texto de la anotación", isPresented: $askingText) {
            TextField("Escribe…", text: $draftText)
            Button("Añadir") { handle.view?.addText(draftText, at: textPoint) }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(AnnoTool.allCases) { t in
                Button { tool = t } label: { Image(systemName: t.symbol) }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tool == t ? Color.accentColor.opacity(0.25) : .clear))
                    .help(t.help)
            }
            Divider().frame(height: 20)
            ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                Button { color = c } label: {
                    Circle().fill(c).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(c == color ? 0.9 : 0.2), lineWidth: c == color ? 2 : 1))
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { handle.view?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless).help("Deshacer")
            Button { handle.view?.clearAll() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Limpiar")
            Divider().frame(height: 20)
            Button { copy() } label: { Label("Copiar", systemImage: "doc.on.doc") }
            Button { save() } label: { Label("Guardar", systemImage: "square.and.arrow.down") }
            Button { addToKlip() } label: { Label("Añadir a Klip", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
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
        sp.begin { resp in if resp == .OK, let url = sp.url { try? png.write(to: url, options: .atomic) } }
    }
    private func addToKlip() {
        guard let img = handle.view?.flattened() else { return }
        onAddToKlip(img)
        onClose()
    }
}
