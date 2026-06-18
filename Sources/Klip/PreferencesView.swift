import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Puente ObservableObject para una API key (OpenAI o Gemini), guardada en archivo local 0600.
@MainActor
final class APIKeyModel: ObservableObject {
    let key: SecretStore.Key
    @Published private(set) var isConfigured = false
    @Published private(set) var last4: String?
    @Published var errorMessage: String?
    @Published var savedOK = false

    init(_ key: SecretStore.Key = .openai) { self.key = key; refresh() }

    func refresh() {
        isConfigured = SecretStore.hasKey(key)
        last4 = SecretStore.last4(key)
    }

    @discardableResult
    func save(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "No se detectó ninguna clave. Pega el texto y vuelve a intentarlo."
            savedOK = false
            return false
        }
        do {
            let ok = try SecretStore.set(trimmed, key)   // escribe y RELEE para confirmar
            if ok {
                errorMessage = nil; savedOK = true
            } else {
                errorMessage = "La clave no se pudo confirmar tras guardarla."; savedOK = false
            }
            refresh()
            return ok
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
            savedOK = false
            refresh()
            return false
        }
    }

    func delete() {
        SecretStore.delete(key); errorMessage = nil; savedOK = false
        refresh()
    }
}

/// Ventana de Preferencias de Klip.
struct PreferencesView: View {
    @ObservedObject var settings = Settings.shared
    var onHotKeyChange: (KeyCombo) -> Void
    var onVoiceHotKeyChange: (KeyCombo) -> Void
    var onMaxItemsChange: () -> Void

    @StateObject private var apiKey = APIKeyModel(.openai)
    @StateObject private var geminiKey = APIKeyModel(.gemini)
    @State private var draftKey = ""
    @State private var showKey = false
    @State private var draftGeminiKey = ""
    @State private var showGeminiKey = false
    @State private var launchAtLogin = LoginItem.shared.isEnabledOrPending
    @State private var loginError: String?
    @State private var accessibilityGranted = Paster.hasAccessibilityPermission

    private let models = ["gpt-4o-mini-transcribe", "whisper-1"]
    private let languages = ["es": "Español", "en": "Inglés", "": "Detectar automáticamente"]

    private var appLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            aboutHeader
            Divider()
            form
        }
        .frame(width: 500, height: 700)
        .onAppear {
            apiKey.refresh(); geminiKey.refresh()
            launchAtLogin = LoginItem.shared.isEnabledOrPending
            accessibilityGranted = Paster.hasAccessibilityPermission
        }
    }

    private var aboutHeader: some View {
        HStack(spacing: 12) {
            if let logo = appLogo {
                Image(nsImage: logo).resizable().frame(width: 54, height: 54)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Klip").font(.title2).bold()
                Text("v\(AppInfo.version) · Gestor de portapapeles para macOS")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let u = URL(string: AppInfo.repoURL) {
                        Link(label: "chevron.left.forwardslash.chevron.right", text: "GitHub", url: u)
                    }
                    if let u = URL(string: AppInfo.issuesURL) {
                        Link(label: "lightbulb", text: "Sugerencias", url: u)
                    }
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(16)
    }

    private var form: some View {
        Form {
            Section("Idioma · Language") {
                Picker("Idioma de la app", selection: $settings.uiLanguage) {
                    Text("Español").tag("es")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                Toggle("Abrir Klip al iniciar sesión", isOn: Binding(
                    get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Pegar automáticamente al elegir un elemento", isOn: $settings.autoPaste)
                if settings.autoPaste && !accessibilityGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Requiere permiso de Accesibilidad.").font(.caption)
                        Button("Conceder…") { Paster.ensureAccessibilityPermission(prompt: true) }.font(.caption)
                    }
                }
                Stepper("Máximo de elementos: \(settings.maxItems)",
                        value: $settings.maxItems, in: 20...1000, step: 10)
                    .onChange(of: settings.maxItems) { _, _ in onMaxItemsChange() }
            }

            Section("Atajos") {
                HStack { Text("Mostrar historial:"); Spacer()
                    HotKeyField(combo: $settings.combo, onChange: onHotKeyChange) }
                HStack { Text("Grabar nota de voz:"); Spacer()
                    HotKeyField(combo: $settings.voiceCombo, onChange: onVoiceHotKeyChange) }
                Text("Pulsa el campo y teclea la combinación, o usa ⌄ para elegir una sugerida.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcripción de voz") {
                Picker("Proveedor", selection: $settings.aiProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Google Gemini").tag("gemini")
                }
                .pickerStyle(.segmented)
                if settings.aiProvider == "openai" {
                    Picker("Modelo", selection: $settings.transcriptionModel) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    LabeledContent("Modelo", value: "gemini-flash-latest")
                }
                Picker("Idioma del audio", selection: $settings.transcriptionLanguage) {
                    ForEach(languages.sorted(by: { $0.value < $1.value }), id: \.key) { Text($1).tag($0) }
                }
                Text(settings.aiProvider == "gemini"
                     ? "Se usará tu clave de Google Gemini (abajo)."
                     : "Se usará tu clave de OpenAI (abajo).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("OpenAI (clave para voz)") {
                keyStatus(apiKey)
                HStack {
                    if showKey {
                        TextField("sk-…", text: $draftKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveOpenAI() }
                    } else {
                        SecureField("sk-…", text: $draftKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveOpenAI() }
                    }
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                }
                HStack {
                    Button("Guardar") { saveOpenAI() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Borrar", role: .destructive) { apiKey.delete() }.disabled(!apiKey.isConfigured)
                    if apiKey.savedOK { Label("Guardada", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                }
                if let err = apiKey.errorMessage { Text(err).font(.caption).foregroundStyle(.red) }
            }

            Section("Google Gemini (clave para voz)") {
                keyStatus(geminiKey)
                HStack {
                    if showGeminiKey {
                        TextField("AIza…", text: $draftGeminiKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveGemini() }
                    } else {
                        SecureField("AIza…", text: $draftGeminiKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveGemini() }
                    }
                    Button { showGeminiKey.toggle() } label: { Image(systemName: showGeminiKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                }
                HStack {
                    Button("Guardar") { saveGemini() }
                        .disabled(draftGeminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Borrar", role: .destructive) { geminiKey.delete() }.disabled(!geminiKey.isConfigured)
                    if geminiKey.savedOK { Label("Guardada", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                }
                if let err = geminiKey.errorMessage { Text(err).font(.caption).foregroundStyle(.red) }
                Text("Obtén tu clave en aistudio.google.com. Se guarda en un archivo local 0600, nunca en el repositorio.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacidad") {
                Toggle("No guardar contraseñas ni datos sensibles", isOn: $settings.ignoreSensitive)
                Text("Klip ignora el contenido que las apps marcan como confidencial (gestores de contraseñas, campos temporales). Los tokens y API keys sueltos se detectan y se guardan aparte como credenciales.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Apps excluidas") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("Ninguna. El contenido copiado en estas apps no se guardará.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(id).font(.system(size: 12)); Spacer()
                        Button(role: .destructive) { settings.removeExcludedApp(id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button { pickApp() } label: { Label("Añadir app…", systemImage: "plus") }
            }
        }
        .formStyle(.grouped)
    }

    /// Fuerza al campo enfocado a confirmar su edición ANTES de leer el binding.
    /// SwiftUI no siempre propaga el texto pegado a `draftKey` antes de que corra la acción del
    /// botón (campo dentro de Form .grouped, sigue siendo first responder): al terminar la edición
    /// del NSTextField, el valor en curso se vuelca al binding. Sin esto, `save` leía el valor viejo.
    private func commitFocusedField() {
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)   // endEditing → vuelca el texto al binding
        }
    }

    private func saveOpenAI() {
        commitFocusedField()
        // Tras volcar el binding en este ciclo de runloop, leer el valor ya actualizado.
        DispatchQueue.main.async {
            if apiKey.save(draftKey) { draftKey = ""; showKey = false }
        }
    }

    private func saveGemini() {
        commitFocusedField()
        DispatchQueue.main.async {
            if geminiKey.save(draftGeminiKey) { draftGeminiKey = ""; showGeminiKey = false }
        }
    }

    @ViewBuilder
    private func keyStatus(_ model: APIKeyModel) -> some View {
        HStack(spacing: 6) {
            if model.isConfigured {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Clave configurada")
                if let l4 = model.last4 {
                    Text("••••\(l4)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Sin clave configurada").foregroundStyle(.secondary)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        switch LoginItem.shared.toggle() {
        case .success:
            launchAtLogin = LoginItem.shared.isEnabledOrPending; loginError = nil
        case .failure(let err):
            if case .requiresApproval = err { LoginItem.shared.openSystemSettings() }
            loginError = err.localizedDescription
            launchAtLogin = LoginItem.shared.isEnabledOrPending
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            settings.addExcludedApp(id)
        }
    }
}

/// Enlace con icono que abre el navegador.
private struct Link: View {
    let label: String
    let text: String
    let url: URL
    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 3) { Image(systemName: label); Text(text) }
        }
        .buttonStyle(.link)
    }
}
