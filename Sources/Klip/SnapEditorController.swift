import AppKit

/// Ventana del editor de capturas: toolbar de herramientas + lienzo. Al copiar/guardar entrega
/// la imagen anotada; al cerrar sin guardar entrega nil.
final class SnapEditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let canvas: AnnotationCanvasView
    private let onFinish: (NSImage?) -> Void
    private var toolButtons: [SnapTool: NSButton] = [:]
    private var finished = false

    init(image: NSImage, onFinish: @escaping (NSImage?) -> Void) {
        self.canvas = AnnotationCanvasView(image: image)
        self.onFinish = onFinish
        super.init()
    }

    func present() {
        let imgSize = canvas.bounds.size
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.85, maxH = screen.height * 0.85 - 52
        let scale = min(1, min(maxW / imgSize.width, maxH / imgSize.height))
        let contentW = max(420, imgSize.width * scale)
        let contentH = imgSize.height * scale + 52   // 52 = barra de herramientas

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Anotar captura — Klip"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))

        // Lienzo dentro de un scroll view (por si la captura es grande).
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH - 52))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = canvas
        scroll.backgroundColor = .underPageBackgroundColor
        content.addSubview(scroll)

        let toolbar = buildToolbar(width: contentW)
        toolbar.frame = NSRect(x: 0, y: contentH - 52, width: contentW, height: 52)
        toolbar.autoresizingMask = [.width, .minYMargin]
        content.addSubview(toolbar)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(canvas)
        selectTool(.arrow)
        self.window = win
    }

    // MARK: - Toolbar

    private func buildToolbar(width: CGFloat) -> NSView {
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .active

        var x: CGFloat = 12
        let y: CGFloat = 10
        let size: CGFloat = 32

        for tool in SnapTool.allCases {
            let b = NSButton(frame: NSRect(x: x, y: y, width: size, height: size))
            b.bezelStyle = .texturedRounded
            b.setButtonType(.toggle)
            b.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.tooltip)
            b.imageScaling = .scaleProportionallyDown
            b.toolTip = tool.tooltip
            b.target = self
            b.action = #selector(toolTapped(_:))
            b.tag = SnapTool.allCases.firstIndex(of: tool) ?? 0
            bar.addSubview(b)
            toolButtons[tool] = b
            x += size + 4
        }

        x += 10
        // Color.
        let well = NSColorWell(frame: NSRect(x: x, y: y, width: 40, height: size))
        well.color = .systemRed
        well.target = self
        well.action = #selector(colorChanged(_:))
        bar.addSubview(well); x += 50

        // Grosor.
        let widths = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne, target: self, action: #selector(widthChanged(_:)))
        widths.frame = NSRect(x: x, y: y, width: 110, height: size)
        widths.selectedSegment = 1
        bar.addSubview(widths); x += 120

        // Deshacer.
        let undo = makeActionButton(symbol: "arrow.uturn.backward", tip: "Deshacer (⌘Z)", action: #selector(undoTapped))
        undo.frame = NSRect(x: x, y: y, width: size, height: size)
        undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = [.command]
        bar.addSubview(undo); x += size + 4

        // Acciones a la derecha.
        let copy = makeTextButton(title: "Copiar", tip: "Copiar (⌘C)", action: #selector(copyTapped))
        copy.frame = NSRect(x: width - 230, y: y, width: 80, height: size); copy.autoresizingMask = [.minXMargin]
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = [.command]
        bar.addSubview(copy)

        let save = makeTextButton(title: "Guardar", tip: "Guardar (⌘S)", action: #selector(saveTapped))
        save.frame = NSRect(x: width - 145, y: y, width: 80, height: size); save.autoresizingMask = [.minXMargin]
        save.keyEquivalent = "s"; save.keyEquivalentModifierMask = [.command]
        bar.addSubview(save)

        let close = makeActionButton(symbol: "xmark", tip: "Cerrar (Esc)", action: #selector(closeTapped))
        close.frame = NSRect(x: width - 52, y: y, width: size, height: size); close.autoresizingMask = [.minXMargin]
        close.keyEquivalent = "\u{1b}"   // Esc
        bar.addSubview(close)

        return bar
    }

    private func makeActionButton(symbol: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        return b
    }

    private func makeTextButton(title: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.toolTip = tip
        b.keyEquivalent = ""
        return b
    }

    // MARK: - Acciones de toolbar

    @objc private func toolTapped(_ sender: NSButton) {
        let tool = SnapTool.allCases[sender.tag]
        selectTool(tool)
    }

    private func selectTool(_ tool: SnapTool) {
        canvas.currentTool = tool
        for (t, b) in toolButtons { b.state = (t == tool) ? .on : .off }
    }

    @objc private func colorChanged(_ sender: NSColorWell) { canvas.currentColor = sender.color }

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        canvas.currentLineWidth = [2.0, 3.0, 6.0][max(0, min(2, sender.selectedSegment))]
    }

    @objc private func undoTapped() { canvas.undo() }

    @objc private func copyTapped() {
        let image = canvas.flattened()
        finish(with: image)
    }

    @objc private func saveTapped() {
        let image = canvas.flattened()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Captura Klip.png"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            self?.finish(with: image)
        }
    }

    @objc private func closeTapped() { finish(with: nil) }

    private func finish(with image: NSImage?) {
        guard !finished else { return }
        finished = true
        window?.orderOut(nil)
        window = nil
        onFinish(image)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        onFinish(nil)
    }
}
