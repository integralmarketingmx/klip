import AppKit

/// Miniatura flotante tras capturar una región (estilo macOS): aparece abajo-derecha con animación
/// de deslizamiento. Si el usuario la toca → editar. Si la ignora (~6 s) → solo guardar en Klip.
final class CapturePreviewController: NSObject {
    private var window: NSPanel?
    private var timer: Timer?
    private var resolved = false
    private let image: NSImage
    private let onEdit: (NSImage) -> Void
    private let onSaveOnly: (NSImage) -> Void
    private let holdSeconds: TimeInterval = 6
    /// Se retiene a sí mismo mientras la miniatura vive (PanelController no necesita gestionarlo).
    private var selfRef: CapturePreviewController?

    init(image: NSImage, onEdit: @escaping (NSImage) -> Void, onSaveOnly: @escaping (NSImage) -> Void) {
        self.image = image
        self.onEdit = onEdit
        self.onSaveOnly = onSaveOnly
        super.init()
    }

    func show() {
        guard let screen = NSScreen.main else { onSaveOnly(image); return }
        selfRef = self
        let vf = screen.visibleFrame

        // Tamaño de la miniatura conservando proporción.
        let maxW: CGFloat = 220, maxH: CGFloat = 150
        let ar = image.size.width / max(1, image.size.height)
        var w = maxW, h = w / ar
        if h > maxH { h = maxH; w = h * ar }
        let pad: CGFloat = 8                       // borde blanco alrededor
        let cw = (w + pad * 2).rounded(), ch = (h + pad * 2).rounded()
        let margin: CGFloat = 18
        let finalX = vf.maxX - cw - margin
        let y = vf.minY + margin
        let startX = vf.maxX + 12                   // empieza fuera de pantalla (derecha)

        let win = NSPanel(contentRect: NSRect(x: startX, y: y, width: cw, height: ch),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.hasShadow = true
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false

        let container = ClickView(frame: NSRect(x: 0, y: 0, width: cw, height: ch))
        container.onClick = { [weak self] in self?.resolveEdit() }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        let iv = NSImageView(frame: NSRect(x: pad, y: pad, width: w, height: h))
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 5
        iv.layer?.masksToBounds = true
        container.addSubview(iv)

        // Badge "Copiado ✓ · ⌘V": avisa que la imagen ya está en el portapapeles, lista para pegar.
        let badge = makeCopiedBadge()
        badge.frame.origin = NSPoint(x: pad + 8, y: pad + h - badge.frame.height - 8)
        container.addSubview(badge)

        win.contentView = container
        win.alphaValue = 0
        win.orderFrontRegardless()
        window = win

        // Entrada: desliza desde la derecha + fade (como la captura de macOS).
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().setFrame(NSRect(x: finalX, y: y, width: cw, height: ch), display: true)
            win.animator().alphaValue = 1
        }

        timer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) { [weak self] _ in
            self?.resolveSaveOnly()
        }
    }

    /// Pastilla translúcida "✓ Copiado · ⌘V" para la esquina de la miniatura.
    private func makeCopiedBadge() -> NSView {
        let text = "✓ Copiado · ⌘V"
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let padX: CGFloat = 8, padY: CGFloat = 4
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size.width + padX * 2, height: size.height + padY * 2))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.82).cgColor
        v.layer?.cornerRadius = 6

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .white
        label.frame = NSRect(x: padX, y: padY - 1, width: size.width, height: size.height)
        v.addSubview(label)
        return v
    }

    private func resolveEdit() {
        guard !resolved else { return }
        resolved = true
        timer?.invalidate()
        closeWindow(animated: false)
        // El panel de la miniatura es "no-activante": al hacer clic NO activa la app, así que
        // el editor nacería sin foco (Esc/⌘Z/cambiar herramienta no responderían). Activamos la
        // app y abrimos el editor en el siguiente ciclo para que sea la ventana key.
        let img = image
        let edit = onEdit
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            edit(img)
        }
        selfRef = nil
    }

    private func resolveSaveOnly() {
        guard !resolved else { return }
        resolved = true
        timer?.invalidate()
        onSaveOnly(image)
        closeWindow(animated: true)
    }

    private func closeWindow(animated: Bool) {
        guard let win = window else { selfRef = nil; return }
        guard animated else { win.orderOut(nil); window = nil; selfRef = nil; return }
        let f = win.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
            win.animator().setFrame(NSRect(x: f.origin.x + f.width + 24, y: f.origin.y,
                                           width: f.width, height: f.height), display: true)
        }, completionHandler: { [weak self] in
            win.orderOut(nil); self?.window = nil; self?.selfRef = nil
        })
    }
}

/// Vista que dispara un closure al hacer clic (la miniatura completa es clicable).
private final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
