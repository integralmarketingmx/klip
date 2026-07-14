import AppKit
import UniformTypeIdentifiers

// MARK: - Combinar / exportar selección
extension PanelController {

    func combineSelectedToPDF(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !exportInFlight else { return }   // no solapar exportaciones
        exportInFlight = true
        modalCount += 1   // protege el panel durante toda la generación + guardado (cierra el hueco de carrera)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Storage.shared.combinedPDF(from: items)
            DispatchQueue.main.async {
                guard let result else {   // nada exportable: avisar en vez de "el botón no hace nada"
                    self.modalCount -= 1; self.exportInFlight = false
                    self.showAlert(L10n.t("export.empty.title"), L10n.t("export.empty.info"))
                    return
                }
                let sp = NSSavePanel()
                sp.allowedContentTypes = [.pdf]
                sp.nameFieldStringValue = "klip.pdf"
                sp.canCreateDirectories = true
                if result.exported < items.count {
                    sp.message = String(format: L10n.t("export.partial"), result.exported, items.count)
                }
                NSApp.activate(ignoringOtherApps: true)
                sp.begin { resp in
                    if resp == .OK, let url = sp.url { try? result.data.write(to: url, options: .atomic) }
                    self.modalCount -= 1; self.exportInFlight = false
                }
            }
        }
    }

    func exportSelectedZip(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !exportInFlight else { return }
        let exportable = Storage.shared.zipExportableCount(items)
        guard exportable > 0 else { showAlert(L10n.t("export.empty.title"), L10n.t("export.empty.info")); return }
        exportInFlight = true
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.zip]
        sp.nameFieldStringValue = "klip-seleccion.zip"
        sp.canCreateDirectories = true
        if exportable < items.count {
            sp.message = String(format: L10n.t("export.partial"), exportable, items.count)
        }
        modalCount += 1
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            guard let self else { return }
            self.modalCount -= 1
            guard resp == .OK, let url = sp.url else { self.exportInFlight = false; return }
            DispatchQueue.global(qos: .userInitiated).async {
                try? Storage.shared.exportItemsZip(items, to: url)
                DispatchQueue.main.async { self.exportInFlight = false }
            }
        }
    }
}
