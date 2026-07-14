import AppKit

// MARK: - Navegación por teclado
extension PanelController {

    /// Intercepta las teclas del panel: Esc (cancelar grabación / cerrar), flechas (navegar),
    /// ⌘1-9 (selección rápida + pegar) y Return/Enter (pegar el seleccionado).
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if isRenaming { return event }   // el diálogo de renombrar maneja sus propias teclas
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 {   // Esc (el monitor siempre corre en el hilo principal)
            if recorder.state == .recording {
                MainActor.assumeIsolated { recorder.cancel() }   // aborta la grabación, no cierra
            } else if !recorder.isRecording {
                hide(restoreFocus: true)                         // no cerrar mientras transcribe
            }
            return nil
        }

        // En modo multi-selección por lote, el teclado NO pega/cierra (rompería el lote en curso): solo
        // navega con flechas; ⌘1-9 / Return no hacen pick. El ratón sigue marcando (onToggleCheck).
        if selection.selecting {
            switch event.keyCode {
            case 125: selection.moveDown(); return nil   // ↓
            case 126: selection.moveUp();   return nil   // ↑
            default:  return event                       // deja escribir en la búsqueda
            }
        }

        // ⌘1..⌘9 → selección rápida + pegar (solo si existe ese índice).
        if flags.contains(.command),
           let ch = event.charactersIgnoringModifiers,
           let n = Int(ch), (1...9).contains(n) {
            if n <= selection.visibleCount { selection.selectQuick(n); pickSelected() }
            return nil
        }
        if flags.contains(.command) { return event }   // no romper ⌘A/⌘C/⌘V en la búsqueda

        switch event.keyCode {
        case 125: selection.moveDown(); return nil    // ↓
        case 126: selection.moveUp();   return nil    // ↑
        case 36, 76: pickSelected();    return nil    // Return / Enter
        default: return event
        }
    }
}
