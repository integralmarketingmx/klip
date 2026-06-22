import AppKit

/// Ventana del editor de capturas: toolbar de herramientas + lienzo. Al copiar/guardar entrega
/// la imagen anotada; al cerrar sin guardar entrega nil.
final class SnapEditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let canvas: AnnotationCanvasView
    private let onFinish: (NSImage?) -> Void
    /// Si está cableado, muestra el botón "Email" en la toolbar: aplana la captura anotada y la entrega
    /// al compositor de email. Lo inyectan PanelController (anotar imagen del historial) y SnapController
    /// (captura nueva). Si es nil, el botón no aparece.
    var onSendEmail: ((NSImage) -> Void)?
    private var emojiPopover: NSPopover?
    /// Emojis frecuentes del picker (mismos que el editor anterior).
    private let emojis = ["😀","👍","🔥","✅","❌","⭐️","➡️","❤️","⚠️","👀","🎯","💡"]
    private var toolButtons: [SnapTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var colorIndex = 0
    private var lastToolWasMarker = false
    /// Paleta para dibujo normal y paleta de tonos de resaltador (se usa con el marcador).
    private let normalColors: [NSColor] = [.systemRed, .systemBlue, .black, .white]
    private let markerColors: [NSColor] = [.systemYellow, .systemGreen, .systemPink, .systemOrange]
    private var palette: [NSColor] { canvas.currentTool == .marker ? markerColors : normalColors }
    private var finished = false

    init(image: NSImage, onFinish: @escaping (NSImage?) -> Void) {
        self.canvas = AnnotationCanvasView(image: image)
        self.onFinish = onFinish
        super.init()
    }

    func present() {
        let imgSize = canvas.bounds.size
        // Siempre en el monitor PRINCIPAL (aunque la captura venga de otro monitor).
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let minBarWidth: CGFloat = 780   // ancho mínimo para que la toolbar no se encime
        let toolbarH: CGFloat = 52
        let titleBarH: CGFloat = 28      // alto de la barra de título de la ventana

        // REGLA: el usuario NUNCA hace scroll. La imagen se escala (solo zoom OUT) para caber entera
        // dentro del monitor principal; el lienzo conserva su resolución nativa vía magnificación del
        // scroll view (las anotaciones y el aplanado siguen a resolución completa).
        let availW = visible.width * 0.96
        let availH = visible.height - toolbarH - titleBarH
        let scale = min(1, min(availW / imgSize.width, availH / imgSize.height))
        let viewW = imgSize.width * scale
        let viewH = imgSize.height * scale
        let contentW = max(minBarWidth, viewW)
        let contentH = viewH + toolbarH

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = L10n.t("win.editor")
        win.isReleasedWhenClosed = false
        win.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))

        // Lienzo dentro de un scroll view con MAGNIFICACIÓN fija = scale (zoom out). El documento queda
        // exactamente del tamaño del área visible → nunca hay barras de scroll.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH - toolbarH))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.allowsMagnification = true
        scroll.minMagnification = scale
        scroll.maxMagnification = scale
        scroll.documentView = canvas
        scroll.magnification = scale
        scroll.backgroundColor = .underPageBackgroundColor
        content.addSubview(scroll)

        let toolbar = buildToolbar(width: contentW)
        toolbar.frame = NSRect(x: 0, y: contentH - 52, width: contentW, height: 52)
        toolbar.autoresizingMask = [.width, .minYMargin]
        content.addSubview(toolbar)

        win.contentView = content
        // Centrar SIEMPRE en el monitor principal (win.frame incluye la barra de título).
        let wf = win.frame
        win.setFrameOrigin(NSPoint(x: visible.minX + (visible.width - wf.width) / 2,
                                   y: visible.minY + (visible.height - wf.height) / 2))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(canvas)
        canvas.currentLineWidth = 4   // trazo por defecto más grueso (más visible)
        selectTool(.arrow)
        // Al seleccionar/deseleccionar un texto, reflejar su color en la paleta de la toolbar.
        canvas.onSelectionChange = { [weak self] in self?.syncColorSelectionFromCanvas() }
        // El menú contextual del lienzo cambia de herramienta: reflejarlo en los botones de la toolbar.
        canvas.onToolPick = { [weak self] tool in self?.selectTool(tool) }
        self.window = win
    }

    // MARK: - Toolbar

    private func buildToolbar(width: CGFloat) -> NSView {
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .active
        let size: CGFloat = 30

        // Grupo izquierdo: herramientas + color + grosor + deshacer.
        let leading = NSStackView()
        leading.orientation = .horizontal
        leading.spacing = 4
        leading.alignment = .centerY
        leading.translatesAutoresizingMaskIntoConstraints = false

        for tool in SnapTool.allCases {
            let b = makeToolButton(tool)
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
            b.heightAnchor.constraint(equalToConstant: 32).isActive = true
            toolButtons[tool] = b
            leading.addArrangedSubview(b)
        }

        leading.addArrangedSubview(separator())

        // Colores: 4 presets (cambian a tonos de resaltador con el marcador) + "más" para el resto.
        for i in 0..<4 {
            let b = makeColorButton(tag: i)
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            colorButtons.append(b)
            leading.addArrangedSubview(b)
        }
        let more = makeActionButton(symbol: "ellipsis.circle", tip: "Más colores…", action: #selector(moreColorTapped))
        more.translatesAutoresizingMaskIntoConstraints = false
        more.widthAnchor.constraint(equalToConstant: 30).isActive = true
        leading.addArrangedSubview(more)

        leading.addArrangedSubview(separator())

        // Grosor: solo dos niveles (fina / gruesa), más gruesos y visibles que antes.
        let widths = NSSegmentedControl(images: [lineImage(4), lineImage(10)],
                                        trackingMode: .selectOne,
                                        target: self, action: #selector(widthChanged(_:)))
        widths.setWidth(40, forSegment: 0); widths.setWidth(40, forSegment: 1)
        widths.selectedSegment = 0
        widths.toolTip = "Grosor del trazo"
        leading.addArrangedSubview(widths)

        leading.addArrangedSubview(separator())

        // Tamaño de texto (afecta al texto seleccionado o al próximo que escribas).
        let smaller = makeActionButton(symbol: "textformat.size.smaller", tip: "Texto más chico", action: #selector(textSmaller))
        let larger = makeActionButton(symbol: "textformat.size.larger", tip: "Texto más grande", action: #selector(textLarger))
        for b in [smaller, larger] {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: size).isActive = true
            leading.addArrangedSubview(b)
        }

        leading.addArrangedSubview(separator())

        // Emoji: popover con emojis frecuentes; al elegir uno se coloca (movible/redimensionable).
        let emoji = makeActionButton(symbol: "face.smiling", tip: "Insertar emoji", action: #selector(emojiTapped(_:)))
        emoji.translatesAutoresizingMaskIntoConstraints = false
        emoji.widthAnchor.constraint(equalToConstant: size).isActive = true
        leading.addArrangedSubview(emoji)

        let undo = makeActionButton(symbol: "arrow.uturn.backward", tip: "Deshacer (⌘Z)", action: #selector(undoTapped))
        undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = [.command]
        undo.translatesAutoresizingMaskIntoConstraints = false
        undo.widthAnchor.constraint(equalToConstant: size).isActive = true
        leading.addArrangedSubview(undo)

        let redo = makeActionButton(symbol: "arrow.uturn.forward", tip: "Rehacer (⌘⇧Z)", action: #selector(redoTapped))
        redo.keyEquivalent = "z"; redo.keyEquivalentModifierMask = [.command, .shift]
        redo.translatesAutoresizingMaskIntoConstraints = false
        redo.widthAnchor.constraint(equalToConstant: size).isActive = true
        leading.addArrangedSubview(redo)

        let clear = makeActionButton(symbol: "trash", tip: "Limpiar todo (deshacer con ⌘Z)", action: #selector(clearTapped))
        clear.translatesAutoresizingMaskIntoConstraints = false
        clear.widthAnchor.constraint(equalToConstant: size).isActive = true
        leading.addArrangedSubview(clear)

        // Grupo derecho: copiar + guardar + cerrar.
        let trailing = NSStackView()
        trailing.orientation = .horizontal
        trailing.spacing = 6
        trailing.alignment = .centerY
        trailing.translatesAutoresizingMaskIntoConstraints = false

        // "Copiar" SOLO copia la imagen anotada al portapapeles (no cierra, no guarda en Klip).
        let copy = makeTextButton(title: "Copiar", tip: "Copiar la imagen al portapapeles (⌘C)", action: #selector(copyTapped))
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = [.command]
        let save = makeTextButton(title: "Guardar", tip: "Guardar como archivo (⌘S)", action: #selector(saveTapped))
        save.keyEquivalent = "s"; save.keyEquivalentModifierMask = [.command]
        let close = makeActionButton(symbol: "xmark", tip: "Cerrar sin guardar (Esc)", action: #selector(closeTapped))
        close.keyEquivalent = "\u{1b}"   // Esc
        close.translatesAutoresizingMaskIntoConstraints = false
        close.widthAnchor.constraint(equalToConstant: size).isActive = true
        trailing.addArrangedSubview(copy)
        trailing.addArrangedSubview(save)
        // Email: solo si el llamador cableó onSendEmail (aplana y abre el compositor).
        if onSendEmail != nil {
            let email = makeActionButton(symbol: "envelope", tip: "Enviar por email la captura anotada", action: #selector(emailTapped))
            email.translatesAutoresizingMaskIntoConstraints = false
            email.widthAnchor.constraint(equalToConstant: size).isActive = true
            trailing.addArrangedSubview(email)
        }
        // "Añadir a Klip" (prominente): copia + guarda en el historial + CIERRA la ventana. Es la acción
        // terminal con la que el usuario avanza sabiendo que ya quedó guardado en Klip. ⌘↩ / Enter.
        let addKlip = makeTextButton(title: "Añadir a Klip", tip: "Copiar y guardar en Klip, y cerrar (⌘↩)", action: #selector(addToKlipTapped))
        addKlip.bezelStyle = .rounded
        // ⌘↩ (no Enter pelón): así no choca con el Enter que confirma el texto que se está escribiendo.
        addKlip.keyEquivalent = "\r"; addKlip.keyEquivalentModifierMask = [.command]
        addKlip.bezelColor = .controlAccentColor
        trailing.addArrangedSubview(addKlip)
        trailing.addArrangedSubview(close)

        bar.addSubview(leading)
        bar.addSubview(trailing)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            leading.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            leading.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -16)
        ])
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
        for (t, b) in toolButtons {
            let on = (t == tool)
            b.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
            b.contentTintColor = on ? .white : .labelColor   // resalta claramente la herramienta activa
        }
        refreshColorSwatches()                                // el marcador muestra tonos de resaltador
        // Solo re-aplicar color cuando la PALETA cambia de tipo (normal↔marcador). Entre herramientas
        // normales se conserva el color elegido (incluido uno libre del selector "más").
        let isMarker = (tool == .marker)
        if isMarker != lastToolWasMarker, colorIndex >= 0 {
            canvas.setColor(palette[min(colorIndex, palette.count - 1)])
        }
        lastToolWasMarker = isMarker
    }

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        canvas.currentLineWidth = sender.selectedSegment == 1 ? 10 : 4   // gruesa / fina
    }

    // MARK: - Color

    @objc private func colorTapped(_ sender: NSButton) {
        colorIndex = sender.tag
        canvas.setColor(palette[min(colorIndex, palette.count - 1)])
        refreshColorSwatches()
    }

    @objc private func moreColorTapped() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        panel.color = canvas.effectiveColor
        panel.isContinuous = true
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        colorIndex = -1                                        // color libre: ningún preset marcado
        canvas.setColor(sender.color)
        refreshColorSwatches()
    }

    /// Si el texto seleccionado usa un color de la paleta, marca ese swatch (si no, ninguno).
    private func syncColorSelectionFromCanvas() {
        colorIndex = palette.firstIndex(where: { Self.approxEqual($0, canvas.effectiveColor) }) ?? -1
        refreshColorSwatches()
    }

    private func refreshColorSwatches() {
        let colors = palette
        for (i, b) in colorButtons.enumerated() {
            b.image = Self.swatchImage(i < colors.count ? colors[i] : .clear)
            b.layer?.cornerRadius = 12
            let on = (i == colorIndex)
            b.layer?.borderWidth = on ? 2.5 : 0
            b.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    // MARK: - Constructores de controles

    private func makeToolButton(_ tool: SnapTool) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(toolTapped(_:)))
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.imageScaling = .scaleProportionallyDown
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        b.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.tooltip)?
            .withSymbolConfiguration(cfg)
        b.toolTip = tool.tooltip
        b.tag = SnapTool.allCases.firstIndex(of: tool) ?? 0
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeColorButton(tag: Int) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(colorTapped(_:)))
        b.isBordered = false
        b.wantsLayer = true
        b.tag = tag
        b.toolTip = "Color"
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return box
    }

    private static func swatchImage(_ color: NSColor) -> NSImage {
        let d: CGFloat = 20
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: d - 4, height: d - 4)).fill()
        NSColor.separatorColor.setStroke()                     // borde para que el blanco se vea
        let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: d - 4, height: d - 4))
        ring.lineWidth = 1; ring.stroke()
        img.unlockFocus()
        return img
    }

    private func lineImage(_ thickness: CGFloat) -> NSImage {
        let w: CGFloat = 24, h: CGFloat = 16
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: h / 2)); p.line(to: NSPoint(x: w - 4, y: h / 2))
        p.lineWidth = thickness; p.lineCapStyle = .round; p.stroke()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private static func approxEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < 0.02
            && abs(x.greenComponent - y.greenComponent) < 0.02
            && abs(x.blueComponent - y.blueComponent) < 0.02
    }

    @objc private func textSmaller() { canvas.bumpFontSize(-4) }
    @objc private func textLarger() { canvas.bumpFontSize(+4) }

    @objc private func undoTapped() { canvas.undo() }
    @objc private func redoTapped() { canvas.redo() }
    @objc private func clearTapped() { canvas.clearAll() }

    @objc private func emojiTapped(_ sender: NSButton) {
        // Reusa un único popover; si ya está visible, lo cierra (toggle).
        if let pop = emojiPopover, pop.isShown { pop.close(); return }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = makeEmojiPicker()
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        emojiPopover = pop
    }

    private func makeEmojiPicker() -> NSViewController {
        let cols = 6, cell: CGFloat = 34, pad: CGFloat = 10
        let rows = Int(ceil(Double(emojis.count) / Double(cols)))
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 4; grid.columnSpacing = 4
        var row: [NSView] = []
        for (i, e) in emojis.enumerated() {
            let b = NSButton(title: e, target: self, action: #selector(emojiPicked(_:)))
            b.isBordered = false
            b.font = .systemFont(ofSize: 22)
            b.toolTip = e
            row.append(b)
            if row.count == cols || i == emojis.count - 1 {
                while row.count < cols { row.append(NSView()) }
                grid.addRow(with: row); row = []
            }
        }
        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: CGFloat(cols) * cell + pad * 2,
                                             height: CGFloat(rows) * cell + pad * 2))
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -pad)
        ])
        let vc = NSViewController()
        vc.view = container
        return vc
    }

    @objc private func emojiPicked(_ sender: NSButton) {
        canvas.insertEmoji(sender.title)
        selectTool(.text)            // pasa a la herramienta de texto para poder mover/redimensionar el emoji
        emojiPopover?.close()
    }

    @objc private func emailTapped() {
        guard let onSendEmail else { return }
        let image = canvas.flattened()
        finish(with: nil)            // cierra el editor sin reinsertar en historial (lo hará el email)
        onSendEmail(image)
    }

    @objc private func copyTapped() {
        // "Copiar" SIEMPRE copia la imagen anotada completa al portapapeles, sin cerrar el editor.
        canvas.copyImageToPasteboard()
    }

    /// Acción terminal: copia + guarda en el historial de Klip + cierra. onFinish(image) hace que el
    /// llamador (SnapController/PanelController) lo añada al historial con copyToClipboard:true.
    @objc private func addToKlipTapped() {
        let image = canvas.flattened()
        finish(with: image)
    }

    @objc private func saveTapped() {
        guard let window else { return }
        let image = canvas.flattened()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Captura Klip.png"
        // Hoja anclada a la ventana del editor (no flotante) para que no quede huérfana si se cierra.
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self else { return }
            guard resp == .OK, let url = panel.url else { return }   // cancelar: el editor sigue abierto
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                self.showError("No se pudo generar el PNG de la captura."); return
            }
            do {
                try png.write(to: url)
                self.finish(with: image)
            } catch {
                // Fallo de escritura (disco lleno, ruta de solo lectura…): avisar y NO cerrar el editor,
                // para no perder la anotación creyendo que se guardó.
                self.showError("No se pudo guardar la captura: \(error.localizedDescription)")
            }
        }
    }

    private func showError(_ msg: String) {
        let a = NSAlert(); a.messageText = "Guardar captura"; a.informativeText = msg
        a.addButton(withTitle: "OK"); a.runModal()
    }

    @objc private func closeTapped() { finish(with: nil) }

    /// Al cerrar el editor, cierra también el NSColorPanel compartido (si se abrió con "más colores"):
    /// de lo contrario seguiría flotando sobre una app de barra de menú sin ventanas, apuntando a un
    /// editor ya destruido.
    private func dismissColorUI() {
        guard NSColorPanel.sharedColorPanelExists else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
    }

    private func finish(with image: NSImage?) {
        guard !finished else { return }
        finished = true
        dismissColorUI()
        window?.orderOut(nil)
        window = nil
        onFinish(image)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        dismissColorUI()
        onFinish(nil)
    }
}
