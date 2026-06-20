import SwiftUI

// MARK: - Botón oficial "Iniciar sesión con Google" (guías de marca de Google)
//
// Sigue las directrices de Google Identity:
//  - Logo "G" a 4 colores (dibujado desde los paths SVG oficiales, nítido a cualquier escala).
//  - Tema claro: fondo #FFFFFF, borde #747775, texto #1F1F1F.
//  - Tema oscuro: fondo #131314, borde #8E918F, texto #E3E3E3.
//  - Alto 40, esquina 4, logo 18, texto "Iniciar sesión con Google" (string oficial en español).
//  - El logo NUNCA cambia de color; el botón no se recolorea.
// Ref: https://developers.google.com/identity/branding-guidelines

/// Logo "G" oficial de Google (viewBox 0 0 48 48), 4 segmentos de color.
struct GoogleGLogo: View {
    var size: CGFloat = 18

    private static let segments: [(String, Color)] = [
        // Rojo #EA4335
        ("M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z",
         Color(red: 0.9176, green: 0.2627, blue: 0.2078)),
        // Azul #4285F4
        ("M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z",
         Color(red: 0.2588, green: 0.5216, blue: 0.9569)),
        // Amarillo #FBBC05
        ("M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z",
         Color(red: 0.9843, green: 0.7373, blue: 0.0196)),
        // Verde #34A853
        ("M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z",
         Color(red: 0.2039, green: 0.6588, blue: 0.3255)),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<Self.segments.count, id: \.self) { i in
                Path(SVGPath.cgPath(Self.segments[i].0)).fill(Self.segments[i].1)
            }
        }
        .frame(width: 48, height: 48)
        .scaleEffect(size / 48)
        .frame(width: size, height: size)
    }
}

/// Botón "Iniciar sesión con Google" con marca oficial. Muestra spinner mientras conecta.
struct GoogleSignInButton: View {
    var connecting: Bool = false
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var bg: Color { scheme == .dark ? Color(red: 0.0745, green: 0.0745, blue: 0.0784) : .white }
    private var border: Color { scheme == .dark ? Color(red: 0.557, green: 0.569, blue: 0.561) : Color(red: 0.455, green: 0.467, blue: 0.459) }
    private var fg: Color { scheme == .dark ? Color(red: 0.890, green: 0.890, blue: 0.890) : Color(red: 0.122, green: 0.122, blue: 0.122) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if connecting {
                    ProgressView().controlSize(.small).frame(width: 18, height: 18)
                } else {
                    GoogleGLogo(size: 18)
                }
                Text("Iniciar sesión con Google")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(fg)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(bg)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini parser de paths SVG (M/L/H/V/C/S/Z, absoluto y relativo) → CGPath
//
// Suficiente para los paths del logo de Google. Coordenadas SVG (y hacia abajo),
// que coinciden con el sistema de SwiftUI Path → no requiere voltear el eje.
enum SVGPath {
    static func cgPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let chars = Array(d)
        var i = 0
        var cmd: Character = " "
        var lastCmd: Character = " "
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl = CGPoint.zero

        func skipSep() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }
        func readNum() -> CGFloat {
            skipSep()
            var s = ""
            var hasDot = false
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == "." { if hasDot { break }; hasDot = true; s.append(c); i += 1 }
                else if c == "e" || c == "E" {
                    s.append(c); i += 1
                    if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                } else { break }
            }
            return CGFloat(Double(s) ?? 0)
        }
        func rel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + cur.x, y: p.y + cur.y) }

        while i < chars.count {
            skipSep()
            if i >= chars.count { break }
            if chars[i].isLetter {
                cmd = chars[i]; i += 1
                if cmd == "Z" || cmd == "z" { path.closeSubpath(); cur = start; lastCmd = cmd; continue }
            }
            switch cmd {
            case "M", "m":
                var p = CGPoint(x: readNum(), y: readNum()); if cmd == "m" { p = rel(p) }
                cur = p; start = p; path.move(to: p)
                cmd = (cmd == "m") ? "l" : "L"   // pares siguientes = lineto implícito
            case "L", "l":
                var p = CGPoint(x: readNum(), y: readNum()); if cmd == "l" { p = rel(p) }
                cur = p; path.addLine(to: p)
            case "H", "h":
                var x = readNum(); if cmd == "h" { x += cur.x }; cur.x = x; path.addLine(to: cur)
            case "V", "v":
                var y = readNum(); if cmd == "v" { y += cur.y }; cur.y = y; path.addLine(to: cur)
            case "C", "c":
                var c1 = CGPoint(x: readNum(), y: readNum())
                var c2 = CGPoint(x: readNum(), y: readNum())
                var e  = CGPoint(x: readNum(), y: readNum())
                if cmd == "c" { c1 = rel(c1); c2 = rel(c2); e = rel(e) }
                path.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; cur = e
            case "S", "s":
                var c2 = CGPoint(x: readNum(), y: readNum())
                var e  = CGPoint(x: readNum(), y: readNum())
                if cmd == "s" { c2 = rel(c2); e = rel(e) }
                let isCubic = lastCmd == "C" || lastCmd == "c" || lastCmd == "S" || lastCmd == "s"
                let c1 = isCubic ? CGPoint(x: 2 * cur.x - lastCtrl.x, y: 2 * cur.y - lastCtrl.y) : cur
                path.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; cur = e
            default:
                i += 1   // comando no soportado: avanza para no colgarse
            }
            lastCmd = cmd
        }
        return path
    }
}
