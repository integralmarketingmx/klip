import AppKit

/// Herramientas de dibujo del editor de capturas (paridad con Lightshot).
enum SnapTool: String, CaseIterable {
    case pencil, line, arrow, rectangle, ellipse, marker, text

    /// SF Symbol propio (no se usan los assets de Lightshot — son IP de Skillbrains).
    var symbol: String {
        switch self {
        case .pencil:    return "pencil.tip"
        case .line:      return "line.diagonal"
        case .arrow:     return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .marker:    return "highlighter"
        case .text:      return "textformat"
        }
    }

    var tooltip: String {
        switch self {
        case .pencil:    return "Lápiz"
        case .line:      return "Línea"
        case .arrow:     return "Flecha"
        case .rectangle: return "Rectángulo"
        case .ellipse:   return "Elipse"
        case .marker:    return "Marcador"
        case .text:      return "Texto"
        }
    }
}

/// Una anotación dibujable. `points` guarda el trazo libre (lápiz/marcador); para formas se usan
/// el primer y último punto; el texto guarda su cadena y su origen.
struct Annotation {
    var id = UUID()
    var tool: SnapTool
    var color: NSColor
    var lineWidth: CGFloat
    var points: [CGPoint]
    var text: String?
    var fontSize: CGFloat = 20   // solo para .text

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    var textFont: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .semibold) }

    /// Rectángulo que ocupa el texto (para selección/hit-testing/mover). nil si no es texto.
    func textBounds() -> CGRect? {
        guard tool == .text, let text, !text.isEmpty else { return nil }
        let size = (text as NSString).size(withAttributes: [.font: textFont])
        let o = points.first ?? .zero
        return CGRect(x: o.x, y: o.y, width: size.width, height: size.height)
    }

    /// Rectángulo de selección/hit-testing para CUALQUIER herramienta (texto o forma). Para formas es
    /// el bounding box de sus puntos, holgado por el grosor del trazo para que sea fácil de tocar.
    func selectionBounds() -> CGRect? {
        if tool == .text { return textBounds() }
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
        let grip = (tool == .marker ? max(lineWidth * 4, 14) : lineWidth) / 2 + 6
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -grip, dy: -grip)
    }

    /// Dibuja la anotación en el contexto actual (coordenadas de la vista, no flipped).
    func draw() {
        color.set()
        switch tool {
        case .pencil:
            strokePath(points, width: lineWidth)
        case .marker:
            color.withAlphaComponent(0.35).set()
            strokePath(points, width: max(lineWidth * 4, 14), round: true)
        case .line:
            let p = NSBezierPath(); p.move(to: start); p.line(to: end)
            p.lineWidth = lineWidth; p.lineCapStyle = .round; p.stroke()
        case .arrow:
            drawArrow(from: start, to: end, width: lineWidth)
        case .rectangle:
            let r = NSBezierPath(rect: rect(start, end)); r.lineWidth = lineWidth; r.stroke()
        case .ellipse:
            let e = NSBezierPath(ovalIn: rect(start, end)); e.lineWidth = lineWidth; e.stroke()
        case .text:
            guard let text, !text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: color
            ]
            (text as NSString).draw(at: start, withAttributes: attrs)
        }
    }

    private func strokePath(_ pts: [CGPoint], width: CGFloat, round: Bool = false) {
        guard pts.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = round ? .square : .round   // marcador: cap cuadrado (trazo de resaltador)
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.line(to: p) }
        path.stroke()
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func drawArrow(from a: CGPoint, to b: CGPoint, width: CGFloat) {
        let line = NSBezierPath(); line.move(to: a); line.line(to: b)
        line.lineWidth = width; line.lineCapStyle = .round; line.stroke()
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = max(12, width * 4)
        let a1 = angle + .pi - .pi / 7
        let a2 = angle + .pi + .pi / 7
        let p1 = CGPoint(x: b.x + cos(a1) * head, y: b.y + sin(a1) * head)
        let p2 = CGPoint(x: b.x + cos(a2) * head, y: b.y + sin(a2) * head)
        let headPath = NSBezierPath()
        headPath.move(to: b); headPath.line(to: p1)
        headPath.move(to: b); headPath.line(to: p2)
        headPath.lineWidth = width; headPath.lineCapStyle = .round; headPath.stroke()
    }
}
