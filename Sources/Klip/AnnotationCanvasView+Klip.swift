import AppKit

// MARK: - Features re-portadas del editor anterior (Fase C del merge Snap)
//
// El editor monolítico AnnotationView.swift se borró al adoptar la arquitectura Snap de Martin.
// Aquí reconstruimos sobre AnnotationCanvasView las features que vivían allí: rehacer, limpiar-todo
// reversible, insertar emoji como anotación movible/redimensionable, y copiar/pegar texto/emoji.
//
// Coordenadas: AnnotationCanvasView usa `isFlipped: false` (origen abajo-izquierda), a diferencia
// del AnnotationView borrado (flipped:true). Por eso `addText` coloca el origen en `point` tal cual
// y deja que `Annotation.draw()` (que dibuja con NSString.draw(at:) en las mismas coordenadas) lo
// pinte donde corresponde — el mismo criterio que usa beginTextEditing/commitActiveText del canvas.
extension AnnotationCanvasView {

    /// Rehacer la última anotación deshecha (⌘⇧Z).
    func redo() {
        guard !redoStack.isEmpty else { return }
        annotations.append(redoStack.removeLast())
        selectedID = nil
        needsDisplay = true
    }

    /// Limpiar todas las anotaciones; guarda un respaldo para poder deshacerlo con ⌘Z.
    func clearAll() {
        commitActiveText()
        clearedBackup = annotations.isEmpty ? nil : annotations
        redoStack.removeAll()
        annotations.removeAll()
        selectedID = nil
        needsDisplay = true
    }

    /// Coloca texto/emoji como una anotación en `point` y la deja seleccionada (para mover/redimensionar).
    func addText(_ s: String, at point: CGPoint) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var ann = Annotation(tool: .text, color: currentColor, lineWidth: currentLineWidth,
                             points: [point], text: t, fontSize: currentFontSize)
        // Emoji/texto pegado nace un poco más grande para que se lea sin tener que agrandarlo a mano.
        if currentFontSize < 28 { ann.fontSize = 28 }
        annotations.append(ann)
        redoStack.removeAll(); clearedBackup = nil
        selectedID = ann.id
        onSelectionChange?()
        needsDisplay = true
    }

    /// Inserta un emoji en el centro del lienzo (queda seleccionado: se puede mover y cambiar de tamaño).
    func insertEmoji(_ emoji: String) {
        addText(emoji, at: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    // MARK: - Copiar / pegar texto-emoji (cadena de responders)

    /// ⌘C: si hay un texto/emoji seleccionado, copia SOLO ese texto al portapapeles y devuelve true.
    /// Si no hay selección de texto, devuelve false para que la toolbar copie la imagen completa.
    @discardableResult
    func copySelectedText() -> Bool {
        guard let id = selectedID,
              let a = annotations.first(where: { $0.id == id }),
              let txt = a.text, !txt.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(txt, forType: .string)
        return true
    }

    /// ⌘V: pega texto/emoji del portapapeles como anotación nueva. Si había una selección, lo coloca
    /// desplazado junto a ella (duplicar); si no, en el centro del lienzo.
    func pasteText() {
        guard let s = NSPasteboard.general.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let id = selectedID, let a = annotations.first(where: { $0.id == id }) {
            addText(s, at: CGPoint(x: a.start.x + 16, y: a.start.y + 16))
        } else {
            addText(s, at: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    @objc func paste(_ sender: Any?) { pasteText() }

    // MARK: - Mover / borrar la selección con teclado

    /// Borra el texto/emoji seleccionado (⌫/Supr). Lo empuja a redoStack para poder rehacerlo.
    func deleteSelection() {
        guard let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        redoStack.append(annotations.remove(at: idx))
        clearedBackup = nil
        selectedID = nil
        onSelectionChange?()
        needsDisplay = true
    }

    /// Desplaza la anotación seleccionada (texto, emoji o forma). En coordenadas no-flipped (origen
    /// abajo-izq), dy>0 sube. Mueve TODOS los puntos para no colapsar formas de 2+ puntos.
    func moveSelection(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].points = annotations[idx].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Durante la edición de texto el NSTextField es first responder, así que esto no interfiere.
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117:                                       // ⌫ borrar / supr
            if selectedID != nil { deleteSelection(); return }
        case 123: if selectedID != nil { moveSelection(dx: -step, dy: 0); return }   // ←
        case 124: if selectedID != nil { moveSelection(dx:  step, dy: 0); return }   // →
        case 125: if selectedID != nil { moveSelection(dx: 0, dy: -step); return }   // ↓ (no-flipped: baja)
        case 126: if selectedID != nil { moveSelection(dx: 0, dy:  step); return }   // ↑ (no-flipped: sube)
        default: break
        }
        super.keyDown(with: event)
    }

    // MARK: - Menú contextual (clic derecho)

    /// Copia la imagen anotada completa al portapapeles SIN cerrar el editor (para el menú contextual).
    func copyImageToPasteboard() {
        let img = flattened()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Copiar", action: #selector(ctxCopy), keyEquivalent: "c")
        let undoIt = menu.addItem(withTitle: "Deshacer", action: #selector(ctxUndo), keyEquivalent: "z")
        undoIt.isEnabled = !annotations.isEmpty || clearedBackup != nil
        let redoIt = menu.addItem(withTitle: "Rehacer", action: #selector(ctxRedo), keyEquivalent: "Z")
        redoIt.isEnabled = !redoStack.isEmpty
        if selectedID != nil {
            menu.addItem(withTitle: "Borrar selección", action: #selector(ctxDelete), keyEquivalent: "\u{8}")
        }
        menu.addItem(.separator())
        let toolsItem = menu.addItem(withTitle: "Herramienta", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for t in SnapTool.allCases {
            let it = sub.addItem(withTitle: t.tooltip, action: #selector(ctxTool(_:)), keyEquivalent: "")
            it.representedObject = t.rawValue
            it.target = self
            it.state = (t == currentTool) ? .on : .off
        }
        toolsItem.submenu = sub
        menu.addItem(.separator())
        menu.addItem(withTitle: "Limpiar todo", action: #selector(ctxClear), keyEquivalent: "")
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }

    @objc private func ctxCopy()  { copyImageToPasteboard() }
    @objc private func ctxUndo()  { undo() }
    @objc private func ctxRedo()  { redo() }
    @objc private func ctxDelete(){ deleteSelection() }
    @objc private func ctxClear() { clearAll() }
    @objc private func ctxTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = SnapTool(rawValue: raw) else { return }
        currentTool = t
        onToolPick?(t)
    }

    // En una app de barra de menú sin menú Edit, ⌘V no llega solo a paste(_:). Lo enrutamos a mano.
    // (⌘C/⌘Z/⌘⇧Z los capturan los botones de la toolbar a nivel de ventana antes que la vista.)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteText()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
