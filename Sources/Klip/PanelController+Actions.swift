import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Acciones de item
extension PanelController {

    func pick(_ item: ClipboardItem) {
        // Nota de voz sin transcripción: no hay texto que pegar → reproducir el audio y dejar el panel abierto.
        if item.kind == .text, (item.text?.isEmpty ?? true) {
            if let af = item.audioFileName { AudioPlayer.shared.toggle(fileName: af) }
            return
        }
        manager.copyToPasteboard(item)
        let target = previousApp
        hide(restoreFocus: false)
        if item.isCredential == true { target?.activate() }   // no auto-pegar secretos: solo copiar + devolver foco
        else { pasteOrRestore(target) }
    }

    func pickSelected() {
        guard let id = selection.selectedID,
              let item = manager.items.first(where: { $0.id == id }) else { return }
        pick(item)
    }

    /// Pega automáticamente en la app previa (si hay permiso y app destino), o solo restaura el foco.
    private func pasteOrRestore(_ target: NSRunningApplication?) {
        guard let target, !target.isTerminated else { return }   // sin destino: solo queda copiado
        if Settings.shared.autoPaste { Paster.paste(into: target) }
        else { target.activate() }
    }

    func copyMarkdown(of item: ClipboardItem) {
        let md = Markdownify.fromText(item.text ?? "")
        let target = previousApp
        manager.setClipboardText(md)
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    func copyAllMarkdown() {
        let md = MarkdownExporter.history(manager.items)
        let target = previousApp
        manager.setClipboardText(md)
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    /// Copia el texto envuelto en un bloque de código Markdown (``` ```), listo para pegar en un chat de IA.
    func copyAsCode(of item: ClipboardItem) {
        guard let t = item.text, !t.isEmpty else { return }
        let target = previousApp
        manager.setClipboardText("```\n\(t)\n```")
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    /// Guarda el texto del elemento como archivo (.txt/.md) para arrastrarlo a una herramienta de IA
    /// cuando el chat no acepta pegarlo (textos/logs muy grandes).
    func saveTextAsFile(_ item: ClipboardItem) {
        guard let t = item.text, !t.isEmpty else { return }
        let sp = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        sp.allowedContentTypes = types
        sp.nameFieldStringValue = (item.name?.isEmpty == false ? item.name! : "klip-texto") + ".txt"
        sp.canCreateDirectories = true
        modalCount += 1   // guard de "hay un panel modal abierto" (no cerrar el panel detrás)
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            if resp == .OK, let url = sp.url { try? t.data(using: .utf8)?.write(to: url, options: .atomic) }
            self?.modalCount -= 1
        }
    }

    func assignSelectedToCollection(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Añadir a colección"
        alert.informativeText = "Nombre de la colección (déjalo vacío para quitar de su colección)."
        alert.addButton(withTitle: "Aceptar")
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel")); cancel.keyEquivalent = "\u{1b}"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        // Precargar solo si TODOS comparten la misma colección; si difieren, dejar vacío (no sobreescribir
        // con una colección arbitraria del lote heterogéneo).
        let current = Set(items.map { $0.collection ?? "" })
        field.stringValue = current.count == 1 ? (current.first ?? "") : ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        isRenaming = true
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        if resp == .alertFirstButtonReturn {
            manager.assignCollection(Set(items.map { $0.id }), to: field.stringValue)
        }
        if panel.isVisible { panel.makeKeyAndOrderFront(nil); selection.focusToken &+= 1 }
    }

    func showGuide() {
        if guideWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Guía de Klip"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: GuideView())
            w.center()
            guideWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        guideWindow?.makeKeyAndOrderFront(nil)
    }

    /// Reintenta transcribir una nota de voz fallida (usa su audio guardado).
    func retryTranscription(_ item: ClipboardItem) {
        guard let af = item.audioFileName, Storage.shared.audioExists(fileName: af) else { return }
        // Evita un segundo reintento (doble-clic) mientras ya está en curso → no duplica la llamada a la API.
        guard manager.items.first(where: { $0.id == item.id })?.preview != ClipboardManager.voiceTranscribing else { return }
        guard AIProvider.hasKey else { onOpenPreferences?(); return }   // sin clave: ofrecer configurarla
        MainActor.assumeIsolated { recorder.retry(itemID: item.id, audioFileName: af) }
    }

    /// Diálogo para ponerle (o cambiarle) el nombre a cualquier elemento. Buscable después.
    func renameItem(_ item: ClipboardItem) {
        let alert = NSAlert()
        alert.messageText = L10n.t("rename.title")
        alert.informativeText = L10n.t("rename.info")
        alert.addButton(withTitle: L10n.t("rename.save"))
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel"))
        cancel.keyEquivalent = "\u{1b}"   // Esc cancela (no se asigna solo en español)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.name ?? ""
        field.placeholderString = L10n.t("rename.placeholder")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        isRenaming = true
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        if resp == .alertFirstButtonReturn { manager.rename(item, to: field.stringValue) }
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            selection.focusToken &+= 1   // devolver el foco al buscador (sin limpiar búsqueda/filtro)
        }
    }

    func saveImage(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = Storage.shared.loadImage(fileName: fn),
              let png = Storage.shared.pngData(from: img) else { return }
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.png]
        sp.nameFieldStringValue = "captura.png"
        sp.canCreateDirectories = true
        modalCount += 1
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            if resp == .OK, let url = sp.url { try? png.write(to: url, options: .atomic) }
            self?.modalCount -= 1
        }
    }
}
