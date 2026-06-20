import CoreGraphics
import Foundation

/// Geometría pura del panel y del editor de anotación: cálculos de frames/posiciones SIN estado de UI.
///
/// Todas las funciones son puras (entran tamaños / `visibleFrame` de la pantalla, salen `NSRect`/`CGSize`),
/// por lo que son testables y están desacopladas de `PanelController`. Este último solo las invoca.
enum PanelPositioner {

    /// Sujeta el origen del panel para que quepa ENTERO dentro del `visibleFrame` (con 8 pt de margen).
    /// `max(lo, hi)` garantiza `lo <= hi` en pantallas más pequeñas que el panel.
    static func clamp(x: CGFloat, y: CGFloat, size: CGSize, into vf: CGRect) -> CGPoint {
        let hiX = max(vf.minX + 8, vf.maxX - size.width - 8)   // garantiza lo <= hi en pantallas pequeñas
        let hiY = max(vf.minY + 8, vf.maxY - size.height - 8)
        let cx = min(max(x, vf.minX + 8), hiX)
        let cy = min(max(y, vf.minY + 8), hiY)
        return CGPoint(x: cx, y: cy)
    }

    /// Posición del panel anclado bajo el botón de la barra de estado: centrado horizontalmente
    /// respecto al botón y justo debajo de él (con `gap`), sujeto al `visibleFrame`.
    static func originBelowStatusButton(buttonFrame: CGRect, size: CGSize, gap: CGFloat,
                                        visibleFrame vf: CGRect) -> CGPoint {
        clamp(x: buttonFrame.midX - size.width / 2,
              y: buttonFrame.minY - gap - size.height, size: size, into: vf)
    }

    /// Posición del panel anclado al cursor (sin botón de barra de estado): centrado bajo el ratón.
    static func originBelowMouse(mouseLocation m: CGPoint, size: CGSize, gap: CGFloat,
                                 visibleFrame vf: CGRect) -> CGPoint {
        clamp(x: m.x - size.width / 2,
              y: m.y - size.height - gap, size: size, into: vf)
    }

    /// Tamaño en pantalla de la captura en el editor de anotación: escala la imagen para que quepa
    /// ENTERA en el `visibleFrame` (zoom out), dejando aire alrededor y hueco para la barra de
    /// herramientas. Nunca amplía (`scale <= 1`). El resultado se redondea hacia abajo.
    static func annotationDisplaySize(imageSize img: CGSize, visibleFrame visible: CGRect,
                                      toolbarHeight toolbarH: CGFloat, margin: CGFloat) -> CGSize {
        let maxW = max(320, visible.width - margin)
        let maxH = max(240, visible.height - margin - toolbarH)
        let scale = min(1, min(maxW / max(img.width, 1), maxH / max(img.height, 1)))
        return CGSize(width: (img.width * scale).rounded(.down),
                      height: (img.height * scale).rounded(.down))
    }
}
