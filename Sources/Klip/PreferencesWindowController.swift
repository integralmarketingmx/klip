import AppKit
import SwiftUI

/// Ventana de Preferencias normal (titulada), distinta del panel flotante.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    convenience init(onHotKeyChange: @escaping (KeyCombo) -> Void,
                     onVoiceHotKeyChange: @escaping (KeyCombo) -> Void,
                     onCaptureHotKeyChange: @escaping (KeyCombo) -> Void,
                     onMaxItemsChange: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Preferencias de Klip"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PreferencesView(onHotKeyChange: onHotKeyChange,
                                      onVoiceHotKeyChange: onVoiceHotKeyChange,
                                      onCaptureHotKeyChange: onCaptureHotKeyChange,
                                      onMaxItemsChange: onMaxItemsChange))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        // Pasar a app "regular" mientras la ventana está abierta: garantiza foco de teclado
        // (necesario para escribir/pegar la API key en el SecureField).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // volver a app de barra de menú (sin Dock)
    }
}
