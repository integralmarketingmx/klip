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
    var onCaptureHotKeyChange: (KeyCombo) -> Void
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

    @State private var costPromptCopied = false

    // MARK: Estado del método de email
    @StateObject private var smtpPass = APIKeyModel(.smtp)
    @State private var draftSMTPPass = ""
    @State private var showSMTPPass = false
    @State private var googleConnecting = false
    @State private var googleError: String?
    @State private var googleConnected = GoogleOAuthClient.shared.isConnected

    private let models = ["gpt-4o-mini-transcribe", "whisper-1"]

    /// Prompt listo para pegar en cualquier IA y verificar los precios vigentes (cambian seguido).
    private let costCheckPrompt = """
    Compara el costo ACTUAL (hoy) de transcribir audio con estos modelos: \
    Google Gemini (gemini-flash-latest, con thinkingBudget 0), \
    OpenAI gpt-4o-mini-transcribe y OpenAI whisper-1. \
    Dame el precio por minuto de cada uno y cuál es el más barato. \
    Cita las páginas oficiales de precios de OpenAI y Google.
    """
    // Modelos de Gemini. Los alias "-latest" evitan 404 por deprecación; se incluyen también
    // versiones fijadas para quien quiera estabilidad de comportamiento.
    private let geminiModels = ["gemini-flash-latest", "gemini-flash-lite-latest",
                                "gemini-pro-latest", "gemini-2.5-flash", "gemini-2.5-pro"]
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

    /// Campos del email que cambian según el método elegido.
    @ViewBuilder
    private var emailMethodFields: some View {
        // Campos comunes a todos los métodos que pasan por el backend (no system mail).
        if settings.mailMethod != .systemMail {
            TextField("Remitente · tu@empresa.com", text: $settings.mailFrom)
                .textFieldStyle(.roundedBorder)
        }

        switch settings.mailMethod {
        case .dwd:
            TextField("Servidor (https://klip…)", text: $settings.uploadEndpoint)
                .textFieldStyle(.roundedBorder)
            SecureField("Token de API (KLIP_API_TOKEN)", text: $settings.mailApiToken)
                .textFieldStyle(.roundedBorder)
            Text("El correo se envía vía Gmail del Workspace (delegación). El token protege el endpoint /send.")
                .font(.caption).foregroundStyle(.secondary)

        case .oauth:
            TextField("Servidor (https://klip…)", text: $settings.uploadEndpoint)
                .textFieldStyle(.roundedBorder)
            SecureField("Token de API (KLIP_API_TOKEN)", text: $settings.mailApiToken)
                .textFieldStyle(.roundedBorder)
            TextField("Google Client ID", text: $settings.googleClientId)
                .textFieldStyle(.roundedBorder)
            SecureField("Google Client Secret", text: $settings.googleClientSecret)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                if googleConnected {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(settings.googleAccountEmail.isEmpty
                         ? "Conectado" : "Conectado como \(settings.googleAccountEmail)")
                        .font(.caption)
                    Spacer()
                    Button("Desconectar") {
                        GoogleOAuthClient.shared.disconnect()
                        googleConnected = false
                    }
                } else {
                    GoogleSignInButton(connecting: googleConnecting) {
                        Task { await connectGoogle() }
                    }
                    .disabled(googleConnecting
                              || settings.googleClientId.isEmpty
                              || settings.googleClientSecret.isEmpty)
                    .opacity((settings.googleClientId.isEmpty || settings.googleClientSecret.isEmpty) ? 0.5 : 1)
                    Spacer()
                }
            }
            if let googleError { Text(googleError).font(.caption).foregroundStyle(.red) }
            Text("Inicia sesión con tu propia cuenta de Google (scope gmail.send). El correo sale como tú. El token de API protege el endpoint /send.")
                .font(.caption).foregroundStyle(.secondary)

        case .smtp:
            TextField("Servidor (https://klip…)", text: $settings.uploadEndpoint)
                .textFieldStyle(.roundedBorder)
            SecureField("Token de API (KLIP_API_TOKEN)", text: $settings.mailApiToken)
                .textFieldStyle(.roundedBorder)
            TextField("SMTP host · smtp.tuempresa.com", text: $settings.smtpHost)
                .textFieldStyle(.roundedBorder)
            TextField("Puerto", value: $settings.smtpPort, format: .number)
                .textFieldStyle(.roundedBorder)
            TextField("Usuario SMTP", text: $settings.smtpUser)
                .textFieldStyle(.roundedBorder)
            HStack {
                Group {
                    if showSMTPPass {
                        TextField("Contraseña SMTP", text: $draftSMTPPass)
                    } else {
                        SecureField(smtpPass.isConfigured ? "•••••• (guardada)" : "Contraseña SMTP",
                                    text: $draftSMTPPass)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button(showSMTPPass ? "Ocultar" : "Ver") { showSMTPPass.toggle() }
                Button("Guardar") { smtpPass.save(draftSMTPPass); draftSMTPPass = "" }
                    .disabled(draftSMTPPass.isEmpty)
            }
            TextField("Remitente SMTP (opcional, default = remitente)", text: $settings.smtpFrom)
                .textFieldStyle(.roundedBorder)
            if let e = smtpPass.errorMessage { Text(e).font(.caption).foregroundStyle(.red) }
            Text("La contraseña SMTP se guarda CIFRADA en este Mac y viaja por HTTPS al backend, que la usa para el envío y NO la persiste. El correo sale por tu servidor SMTP (STARTTLS).")
                .font(.caption).foregroundStyle(.secondary)

        case .systemMail:
            Text("Al enviar, Klip abre el compositor de correo nativo (Mail.app o tu cliente por defecto) con la imagen adjunta. No requiere servidor ni token; funciona con cualquier cuenta.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func connectGoogle() async {
        googleError = nil
        googleConnecting = true
        defer { googleConnecting = false }
        do {
            _ = try await GoogleOAuthClient.shared.connect()
            googleConnected = true
        } catch {
            googleError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

            Section("Email (enviar capturas)") {
                Picker("Método de envío", selection: $settings.mailMethod) {
                    ForEach(MailMethod.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                emailMethodFields
            }

            Section("Atajos") {
                HStack { Text("Mostrar historial:"); Spacer()
                    HotKeyField(combo: $settings.combo, onChange: onHotKeyChange) }
                HStack { Text("Grabar nota de voz:"); Spacer()
                    HotKeyField(combo: $settings.voiceCombo, onChange: onVoiceHotKeyChange) }
                HStack { Text("Capturar y anotar:"); Spacer()
                    HotKeyField(combo: $settings.captureCombo, onChange: onCaptureHotKeyChange) }
                Text("Pulsa el campo y teclea la combinación, o usa ⌄ para elegir una sugerida.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Reemplazar ⌘⇧4 de macOS", isOn: Binding(
                    get: { settings.overrideSystemCapture },
                    set: { setOverrideCmd4($0) }))
                Text("Desactiva la captura del sistema (⌘⇧4) y se la asigna a Klip. Al apagarlo, la restaura y Klip vuelve a ⌘⇧2.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcripción de voz") {
                Picker("Proveedor principal", selection: $settings.aiProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Google Gemini").tag("gemini")
                }
                .pickerStyle(.segmented)
                if settings.aiProvider == "openai" {
                    Picker("Modelo", selection: $settings.transcriptionModel) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    Picker("Modelo", selection: $settings.geminiModel) {
                        ForEach(geminiModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker("Idioma del audio", selection: $settings.transcriptionLanguage) {
                    ForEach(languages.sorted(by: { $0.value < $1.value }), id: \.key) { Text($1).tag($0) }
                }
                Toggle(settings.aiProvider == "gemini"
                       ? "Usar OpenAI si Gemini falla"
                       : "Usar Gemini si OpenAI falla", isOn: $settings.transcriptionFallback)
                Text(settings.aiProvider == "gemini"
                     ? "Prioridad: Gemini primero; si su clave no sirve, reintenta con OpenAI (cuando haya clave)."
                     : "Prioridad: OpenAI primero; si su clave no sirve, reintenta con Gemini (cuando haya clave).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Costo aproximado por transcripción") {
                costRow(rank: 1, name: "Gemini", model: "gemini-flash-latest", perMin: "~$0.0020/min", cheapest: true)
                costRow(rank: 2, name: "OpenAI mini", model: "gpt-4o-mini-transcribe", perMin: "~$0.003/min", cheapest: false)
                costRow(rank: 3, name: "OpenAI Whisper", model: "whisper-1 (modelo viejo)", perMin: "~$0.006/min", cheapest: false)
                Text("Medido en jun 2026 con ~1 min de audio. Gemini va sin “thinking” (más barato). **Los precios de las APIs cambian** — verifica los vigentes:")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(costCheckPrompt, forType: .string)
                        costPromptCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { costPromptCopied = false }
                    } label: {
                        Label(costPromptCopied ? "Prompt copiado ✓" : "Copiar prompt para verificar precios",
                              systemImage: costPromptCopied ? "checkmark" : "doc.on.doc")
                    }
                    Link(label: "link", text: "Precios OpenAI", url: URL(string: "https://openai.com/api/pricing")!)
                        .font(.caption)
                    Link(label: "link", text: "Precios Gemini", url: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
                        .font(.caption)
                }
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

    @ViewBuilder
    private func costRow(rank: Int, name: String, model: String, perMin: String, cheapest: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption2).bold()
                .frame(width: 16, height: 16)
                .background(Circle().fill(cheapest ? Color.green.opacity(0.22) : Color.secondary.opacity(0.15)))
                .foregroundStyle(cheapest ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(model).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(perMin).font(.system(.body, design: .monospaced))
            if cheapest {
                Text("más barato")
                    .font(.caption2).bold().foregroundStyle(.green)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.16)))
            }
        }
    }

    /// Activa/desactiva "Reemplazar ⌘⇧4": desactiva el atajo del sistema y asigna ⌘⇧4 a Klip
    /// (o lo restaura y vuelve Klip a ⌘⇧2).
    private func setOverrideCmd4(_ on: Bool) {
        // Lo rápido en el hilo principal (que el switch responda al instante).
        settings.overrideSystemCapture = on
        let combo = on ? KeyCombo.cmdShift4Combo : .defaultCaptureCombo
        settings.captureCombo = combo
        onCaptureHotKeyChange(combo)                            // re-registra el hotkey global de Klip
        // Lo lento (defaults + activateSettings) en segundo plano: no congela la UI.
        DispatchQueue.global(qos: .userInitiated).async {
            SystemShortcuts.setMacScreenshotAreaEnabled(!on)   // on → desactiva ⌘⇧4 de macOS
        }
        if on { settings.pendingCmd4Verify = true; promptReloginForCmd4() }
        else  { settings.pendingCmd4Verify = false }
    }

    /// Modal: ⌘⇧4 necesita cerrar sesión para liberarse. Ofrece cerrar sesión ahora.
    private func promptReloginForCmd4() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Falta un paso para usar ⌘⇧4"
        alert.informativeText = "Para que ⌘⇧4 abra Klip en vez de la captura de macOS, necesitas cerrar sesión y volver a entrar una vez. macOS suelta el atajo solo al reiniciar tu sesión (no apaga la Mac). Klip lo verificará al volver."
        alert.addButton(withTitle: "Cerrar sesión ahora")     // .alertFirstButtonReturn
        alert.addButton(withTitle: "Lo haré después")          // .alertSecondButtonReturn
        let cancel = alert.addButton(withTitle: "Cancelar (usar ⌘⇧2)")  // .alertThirdButtonReturn
        cancel.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            SystemShortcuts.logOut()                           // macOS pide su confirmación estándar
        case .alertThirdButtonReturn:
            setOverrideCmd4(false)                             // revertir: vuelve a ⌘⇧2 y restaura macOS
        default:
            break                                              // "Después": queda pendiente, verifica al re-login
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
