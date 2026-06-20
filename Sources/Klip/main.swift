import AppKit

// Punto de entrada. App accesoria (sin icono en el Dock); vive en la barra de menú.
// El arranque corre en el hilo principal: AppDelegate es @MainActor (Consejo C2), así que se
// construye dentro de un contexto MainActor.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(ProcessInfo.processInfo.environment["KLIP_REGULAR"] == nil ? .accessory : .regular)
    app.run()
}
