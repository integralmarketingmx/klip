import AppKit
import Carbon.HIToolbox
import Combine
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let recentsMenu = NSMenu()
    private static let recentsDF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale.current; f.dateFormat = "dd MMM HH:mm"; return f
    }()
    private let manager = ClipboardManager()
    private var panelController: PanelController!
    private var hotKey: HotKey?
    private var voiceHotKey: HotKey?
    private var captureHotKey: HotKey?
    private var lastGoodCombo = Settings.shared.combo
    private var lastGoodVoiceCombo = Settings.shared.voiceCombo
    private var lastGoodCaptureCombo = Settings.shared.captureCombo
    private var prefsController: PreferencesWindowController?
    private var launchItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Klip")?
                .withSymbolConfiguration(cfg)
        }
        installMainMenu()
        buildMenu()
        panelController = PanelController(manager: manager, statusItem: statusItem)
        panelController.onOpenPreferences = { [weak self] in self?.openPreferences() }
        manager.start()
        // Si "reemplazar ⌘⇧4" está activo: re-asegura el atajo del sistema desactivado y re-afirma ⌘⇧4
        // como combo de Klip (por si un fallback previo lo revirtió a ⌘⇧2).
        if Settings.shared.overrideSystemCapture {
            SystemShortcuts.setMacScreenshotAreaEnabled(false)
            Settings.shared.captureCombo = .cmdShift4Combo
        }
        setupHotKeys()
        verifyCmd4IfPending()
        maybeEnableLoginOnce()
        Settings.shared.$uiLanguage.dropFirst().sink { [weak self] _ in self?.buildMenu() }.store(in: &cancellables)
        // Aviso NO-modal cuando el guardado del historial falla repetidamente (Consejo C6).
        NotificationCenter.default.addObserver(self, selector: #selector(handlePersistenceFailure(_:)),
                                               name: Storage.persistenceFailureNotification, object: nil)
    }

    /// Muestra una advertencia no-bloqueante (ventana flotante) cuando Klip no logra guardar el
    /// historial en disco tras varios reintentos. No usa runModal para no congelar la interacción.
    private var persistenceWarningShown = false
    @objc private func handlePersistenceFailure(_ note: Notification) {
        guard !persistenceWarningShown else { return }   // un solo aviso por sesión
        persistenceWarningShown = true
        let info = (note.userInfo?["message"] as? String) ?? ""
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Klip no pudo guardar el historial"
        a.informativeText = "Hubo fallos repetidos al escribir en disco. Revisa el espacio libre o los permisos."
            + (info.isEmpty ? "" : "\n\n(\(info))")
        let ok = a.addButton(withTitle: "OK")
        ok.target = self
        ok.action = #selector(dismissPersistenceWarning)
        NSApp.activate(ignoringOtherApps: true)
        // Ventana flotante presentada SIN runModal: no bloquea el resto de la app.
        persistenceAlertWindow = a.window
        a.window.level = .floating
        a.window.center()
        a.window.makeKeyAndOrderFront(nil)
    }

    private var persistenceAlertWindow: NSWindow?
    @objc private func dismissPersistenceWarning() {
        persistenceAlertWindow?.orderOut(nil)
        persistenceAlertWindow = nil
        persistenceWarningShown = false   // permite avisar de nuevo si vuelve a fallar más tarde
    }

    // Una app accesoria (.accessory) no tiene menú principal, así que los campos de texto de
    // SwiftUI no reciben ⌘X/⌘C/⌘V/⌘A (no hay menú "Editar" que enrute esos atajos por la
    // cadena de responders). Instalamos un menú principal mínimo con un menú Editar estándar.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // Menú de la app (necesario para que el menú Editar aparezca como segundo).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Menú Editar con los atajos estándar (target nil → cadena de responders).
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "\(L10n.t("menu.show"))   \(Settings.shared.combo.displayString)",
                     action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "\(L10n.t("rec.record"))   \(Settings.shared.voiceCombo.displayString)",
                     action: #selector(startVoice), keyEquivalent: "")
        // Captura + anotación (editor unificado: base del jefe + mejoras de Mike).
        menu.addItem(withTitle: "\(L10n.t("capture.annotate"))   \(Settings.shared.captureCombo.displayString)",
                     action: #selector(captureAnnotate), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("capture.full"), action: #selector(captureAnnotateFull), keyEquivalent: "")
        menu.addItem(.separator())
        let recents = NSMenuItem(title: "Recientes", action: nil, keyEquivalent: "")
        recentsMenu.delegate = self
        recents.submenu = recentsMenu
        menu.addItem(recents)
        menu.addItem(.separator())
        let prefs = menu.addItem(withTitle: L10n.t("menu.prefs"), action: #selector(openPreferences), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = [.command]
        let launch = NSMenuItem(title: L10n.t("menu.login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = LoginItem.shared.isEnabledOrPending ? .on : .off
        menu.addItem(launch); self.launchItem = launch
        menu.addItem(withTitle: L10n.t("menu.autopaste"), action: #selector(enableAutoPaste), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("act.guide"), action: #selector(showGuideMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.export"), action: #selector(exportBackup), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("menu.import"), action: #selector(importBackup), keyEquivalent: "")
        // Submenú "Borrar historial" por rango de tiempo (borra lo más reciente; conserva los fijados).
        let clearItem = NSMenuItem(title: L10n.t("menu.clear"), action: nil, keyEquivalent: "")
        let clearMenu = NSMenu()
        let ranges: [(String, Int)] = [
            ("Última hora", 3600),
            ("Último día", 86_400),
            ("Última semana", 604_800),
            ("Último mes", 2_592_000),
            ("Todo", 0)
        ]
        for (title, secs) in ranges {
            if secs == 0 { clearMenu.addItem(.separator()) }
            let it = clearMenu.addItem(withTitle: title, action: #selector(clearRange(_:)), keyEquivalent: "")
            it.tag = secs
            it.target = self
        }
        clearItem.submenu = clearMenu
        menu.addItem(clearItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { if $0.target == nil { $0.target = self } }
        statusItem.menu = menu
    }

    private func makePanelHotKey(_ c: KeyCombo) {
        hotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 1) { [weak self] in
            self?.panelController.toggle()
        }
    }
    private func makeVoiceHotKey(_ c: KeyCombo) {
        voiceHotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 2) { [weak self] in
            self?.panelController.toggleVoiceRecording()
        }
    }
    private func makeCaptureHotKey(_ c: KeyCombo) {
        captureHotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 3) { [weak self] in
            self?.panelController.captureAndAnnotate(fullScreen: false)
        }
    }

    /// Hook que corre al arrancar (Klip inicia con la sesión): si quedó pendiente activar ⌘⇧4,
    /// verifica si ya se registró (macOS lo soltó tras el re-login) y avisa el éxito una sola vez.
    private func verifyCmd4IfPending() {
        guard Settings.shared.pendingCmd4Verify, Settings.shared.overrideSystemCapture else { return }
        // Éxito = el hotkey ⌘⇧4 se registró (captureHotKey != nil con el combo ⌘⇧4).
        let success = captureHotKey != nil && Settings.shared.captureCombo == .cmdShift4Combo
        guard success else { return }   // aún no: sigue pendiente, se reintenta el próximo arranque
        Settings.shared.pendingCmd4Verify = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "⌘⇧4 listo ✓"
            alert.informativeText = "Ahora ⌘⇧4 abre la captura de Klip en vez de la de macOS."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func setupHotKeys() {
        makePanelHotKey(Settings.shared.combo)
        makeVoiceHotKey(Settings.shared.voiceCombo)
        makeCaptureHotKey(Settings.shared.captureCombo)
        // Si una combinación persistida colisiona con otra al arrancar (HotKey.init devuelve nil), el
        // atajo quedaría muerto toda la sesión. Recuperar con su atajo por defecto para no perderlo.
        if hotKey == nil, Settings.shared.combo != .defaultCombo {
            Settings.shared.combo = .defaultCombo; lastGoodCombo = .defaultCombo; makePanelHotKey(.defaultCombo)
        }
        if voiceHotKey == nil, Settings.shared.voiceCombo != .defaultVoiceCombo {
            Settings.shared.voiceCombo = .defaultVoiceCombo; lastGoodVoiceCombo = .defaultVoiceCombo; makeVoiceHotKey(.defaultVoiceCombo)
        }
        // No revertir a ⌘⇧2 si el usuario activó "reemplazar ⌘⇧4": ese combo (⌘⇧4) puede fallar al
        // registrarse hasta que macOS suelte el atajo (tras cerrar sesión). Conservarlo.
        if captureHotKey == nil, Settings.shared.captureCombo != .defaultCaptureCombo,
           !Settings.shared.overrideSystemCapture {
            Settings.shared.captureCombo = .defaultCaptureCombo; lastGoodCaptureCombo = .defaultCaptureCombo; makeCaptureHotKey(.defaultCaptureCombo)
        }
    }

    private func applyCaptureHotKey(_ combo: KeyCombo) {
        let ok: Bool
        if captureHotKey == nil { makeCaptureHotKey(combo); ok = (captureHotKey != nil) }   // estaba muerto: re-crear
        else { ok = captureHotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodCaptureCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.captureCombo = lastGoodCaptureCombo }
        buildMenu()
    }

    private func applyHotKey(_ combo: KeyCombo) {
        let ok: Bool
        if hotKey == nil { makePanelHotKey(combo); ok = (hotKey != nil) }
        else { ok = hotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.combo = lastGoodCombo }   // colisión: revertir
        buildMenu()
    }

    private func applyVoiceHotKey(_ combo: KeyCombo) {
        let ok: Bool
        if voiceHotKey == nil { makeVoiceHotKey(combo); ok = (voiceHotKey != nil) }
        else { ok = voiceHotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodVoiceCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.voiceCombo = lastGoodVoiceCombo }
        buildMenu()
    }

    private func maybeEnableLoginOnce() {
        let key = "didAutoEnableLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        LoginItem.shared.registerIfNeeded()
        launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
    }

    // Submenú "Recientes": se reconstruye cada vez que se abre.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentsMenu else { return }
        menu.removeAllItems()
        let items = manager.items.sorted { $0.createdAt > $1.createdAt }.prefix(10)
        if items.isEmpty {
            let empty = NSMenuItem(title: "Sin elementos", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for it in items {
            let icon = it.isVoiceNote == true ? "🎙 " : (it.kind == .image ? "🖼 " : (it.isCredential == true ? "🔑 " : ""))
            let body: String
            if let nm = it.name, !nm.isEmpty { body = String(nm.prefix(45)) }   // nombre puesto por el usuario
            else if it.isCredential == true { body = CredentialDetector.masked(it.text ?? "") }
            else if it.isVoiceNote == true {
                // texto transcrito (evita doble 🎙); si aún no hay, usar el preview sin el emoji.
                let tx = (it.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                body = tx.isEmpty ? String(it.preview.drop(while: { $0 == "🎙" || $0 == " " }).prefix(45))
                                  : String(tx.prefix(45))
            }
            else { body = String(it.preview.prefix(45)) }
            let mi = NSMenuItem(title: "\(Self.recentsDF.string(from: it.createdAt))   \(icon)\(body)",
                                action: #selector(pasteRecent(_:)), keyEquivalent: "")
            mi.representedObject = it.id
            mi.target = self
            menu.addItem(mi)
        }
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = manager.items.first(where: { $0.id == id }) else { return }
        // Nota de voz sin transcripción: no hay texto que copiar → reproducir su audio.
        if item.kind == .text, (item.text?.isEmpty ?? true) {
            if let af = item.audioFileName { AudioPlayer.shared.toggle(fileName: af) }
            return
        }
        manager.copyToPasteboard(item)   // queda en el portapapeles, listo para pegar
    }

    @objc private func showPanel() { panelController.show() }
    @objc private func startVoice() { panelController.toggleVoiceRecording() }
    @objc private func captureAnnotate() { panelController.captureAndAnnotate(fullScreen: false) }
    @objc private func captureAnnotateFull() { panelController.captureAndAnnotate(fullScreen: true) }
    @objc private func showGuideMenu() { panelController.showGuide() }

    @objc private func openPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController(
                onHotKeyChange: { [weak self] combo in self?.applyHotKey(combo) },
                onVoiceHotKeyChange: { [weak self] combo in self?.applyVoiceHotKey(combo) },
                onCaptureHotKeyChange: { [weak self] combo in self?.applyCaptureHotKey(combo) },
                onMaxItemsChange: { [weak self] in self?.manager.applyMaxItems() })
        }
        prefsController?.show()
    }

    @objc private func toggleLaunchAtLogin() {
        switch LoginItem.shared.toggle() {
        case .success:
            launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
        case .failure(let err):
            if case .requiresApproval = err { LoginItem.shared.openSystemSettings() }
            let alert = NSAlert()
            alert.messageText = "Inicio automático"
            alert.informativeText = err.localizedDescription
            alert.runModal()
            launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
        }
    }

    @objc private func enableAutoPaste() {
        if Paster.ensureAccessibilityPermission(prompt: true) {
            let a = NSAlert()
            a.messageText = "Pegado automático activado"
            a.informativeText = "Klip ya puede pegar automáticamente al elegir un elemento del historial."
            a.runModal()
        }
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("clear.title")
        alert.informativeText = L10n.t("clear.info")
        let del = alert.addButton(withTitle: L10n.t("clear.confirm"))
        del.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel"))
        cancel.keyEquivalent = "\u{1b}"   // Esc cancela (no se asigna solo en español)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { manager.clearAll() }
    }

    /// Borra el historial por rango: tag = segundos hacia atrás (0 = todo). Conserva los fijados.
    @objc private func clearRange(_ sender: NSMenuItem) {
        let secs = sender.tag
        let label = sender.title.lowercased()
        let count = secs == 0 ? manager.items.count : manager.countSince(Date(timeIntervalSinceNow: -Double(secs)))
        guard count > 0 else {
            let none = NSAlert()
            none.messageText = "Nada que borrar"
            none.informativeText = "No hay elementos en ese rango (los fijados no se borran)."
            none.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            none.runModal()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = secs == 0 ? "¿Borrar todo el historial?" : "¿Borrar el historial de \(label)?"
        alert.informativeText = "Se eliminarán \(count) elemento\(count == 1 ? "" : "s"). Los fijados se conservan. No se puede deshacer."
        let del = alert.addButton(withTitle: "Borrar")
        del.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel"))
        cancel.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if secs == 0 { manager.clearAll() }
        else { manager.clearSince(Date(timeIntervalSinceNow: -Double(secs))) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func exportBackup() {
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.zip]
        sp.nameFieldStringValue = "Klip-backup.zip"
        sp.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            guard resp == .OK, let url = sp.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {   // ditto + copia pesada: fuera de main
                do { try Storage.shared.exportBackup(to: url) }
                catch { DispatchQueue.main.async { self?.showAlert(L10n.t("export.fail"), error.localizedDescription) } }
            }
        }
    }

    @objc private func importBackup() {
        let op = NSOpenPanel()
        op.allowedContentTypes = [.zip]
        op.allowsMultipleSelection = false
        op.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        op.begin { [weak self] resp in
            guard let self, resp == .OK, let url = op.url else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.t("import.title")
            alert.informativeText = L10n.t("import.info")
            let ok = alert.addButton(withTitle: L10n.t("import.confirm")); ok.hasDestructiveAction = true
            let cancel = alert.addButton(withTitle: L10n.t("common.cancel")); cancel.keyEquivalent = "\u{1b}"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.manager.pauseMonitoring()   // que el poll no escriba en el store durante el import
            DispatchQueue.global(qos: .userInitiated).async {   // ditto + copia pesada: fuera de main
                do {
                    let items = try Storage.shared.importBackup(from: url)
                    DispatchQueue.main.async { self.manager.reload(items); self.manager.resumeMonitoring() }
                } catch {
                    DispatchQueue.main.async { self.showAlert(L10n.t("import.fail"), error.localizedDescription); self.manager.resumeMonitoring() }
                }
            }
        }
    }

    private func showAlert(_ title: String, _ info: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = info
        a.addButton(withTitle: "OK"); a.runModal()
    }
}
