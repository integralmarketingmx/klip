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
        selectedTextID = nil
        needsDisplay = true
    }

    /// Limpiar todas las anotaciones; guarda un respaldo para poder deshacerlo con ⌘Z.
    func clearAll() {
        commitActiveText()
        clearedBackup = annotations.isEmpty ? nil : annotations
        redoStack.removeAll()
        annotations.removeAll()
        selectedTextID = nil
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
        selectedTextID = ann.id
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
        guard let id = selectedTextID,
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
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) {
            addText(s, at: CGPoint(x: a.start.x + 16, y: a.start.y + 16))
        } else {
            addText(s, at: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    @objc func paste(_ sender: Any?) { pasteText() }

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
