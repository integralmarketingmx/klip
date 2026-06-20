import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Compositor de email para enviar una captura por correo (vía el server Klip /send).
/// Campos Para/CC/CCO, asunto, notas (cuerpo) y un toggle "al dueño / a otra persona".
/// Sigue el mockup `docs/mockups/visor-email-compositor.html`. Alcance: que compile y
/// mande la request; la UI no busca ser perfecta.
struct EmailComposerView: View {
    /// Destino sugerido cuando es "al dueño del link" (puede venir vacío en pruebas).
    var ownerEmail: String
    /// Slug Klip de la captura, para correlación en el server.
    var slug: String
    /// PNG opcional a adjuntar.
    var attachment: Data?
    /// Asunto y cuerpo iniciales.
    var initialSubject: String
    var initialBody: String
    /// Callbacks de cierre.
    var onClose: () -> Void

    enum Audience { case owner, other }

    @State private var audience: Audience = .owner
    @State private var to: String = ""
    @State private var cc: String = ""
    @State private var bcc: String = ""
    @State private var subject: String
    @State private var bodyText: String
    @State private var showCCBCC = false
    @State private var sending = false
    @State private var errorText: String?
    @State private var sent = false
    @State private var extraAttachments: [MailAttachment] = []

    @ObservedObject private var settings = Settings.shared

    init(ownerEmail: String, slug: String, attachment: Data?,
         initialSubject: String, initialBody: String, onClose: @escaping () -> Void) {
        self.ownerEmail = ownerEmail
        self.slug = slug
        self.attachment = attachment
        self.initialSubject = initialSubject
        self.initialBody = initialBody
        self.onClose = onClose
        _subject = State(initialValue: initialSubject)
        _bodyText = State(initialValue: initialBody)
        _to = State(initialValue: ownerEmail)
        // Si no hay dueño del link (yo soy el creador del klip), arranca en "a otra persona":
        // no tiene sentido ofrecer "al dueño" porque el dueño soy yo.
        _audience = State(initialValue: ownerEmail.isEmpty ? .other : .owner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // El selector "al dueño / a otra persona" solo aparece cuando hay un dueño del
                    // link (klip de otra persona). Si yo soy el creador, voy directo al destinatario.
                    if !ownerEmail.isEmpty { audienceSegment }
                    field(label: "Para", text: $to, placeholder: "destinatario@empresa.com")
                    HStack {
                        Spacer()
                        Button(showCCBCC ? "Ocultar CC · CCO" : "CC · CCO") { showCCBCC.toggle() }
                            .buttonStyle(.link).font(.caption)
                    }
                    if showCCBCC {
                        field(label: "CC", text: $cc, placeholder: "copias visibles, separadas por coma")
                        field(label: "CCO", text: $bcc, placeholder: "copias ocultas (bcc)")
                    }
                    field(label: "De", text: $settings.mailFrom, placeholder: "tu@empresa.com")
                    field(label: "Asunto", text: $subject, placeholder: "Asunto")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notas / mensaje (cuerpo del correo)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 90)
                            .font(.system(size: 13))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    }

                    if attachment != nil {
                        attachmentRow(name: "captura.png", detail: "PNG · se adjunta al correo", onRemove: nil)
                    }
                    ForEach(extraAttachments) { att in
                        attachmentRow(name: att.name,
                                      detail: "\(att.mime) · \(byteLabel(att.data.count))",
                                      onRemove: { extraAttachments.removeAll { $0.id == att.id } })
                    }
                    Button { addAttachment() } label: {
                        Label("Adjuntar archivo…", systemImage: "paperclip.badge.plus")
                    }
                    .buttonStyle(.link).font(.caption)

                    if let errorText {
                        Text(errorText).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .cornerRadius(6)
            Text("Enviar captura").font(.headline)
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var audienceSegment: some View {
        Picker("", selection: $audience) {
            Text("Al dueño del link").tag(Audience.owner)
            Text("A otra persona").tag(Audience.other)
        }
        .pickerStyle(.segmented)
        .onChange(of: audience) { _, newValue in
            if newValue == .owner { to = ownerEmail } else { to = "" }
        }
    }

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).frame(width: 50, alignment: .leading)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.2)), alignment: .bottom)
    }

    /// Texto del pie según el método elegido.
    private var methodHint: String {
        switch settings.mailMethod {
        case .oauth:      return "🔒 Se envía con tu cuenta de Google Workspace conectada (solo tú, como remitente)."
        case .smtp:       return "🔒 Se envía por tu servidor SMTP."
        case .systemMail: return "✉️ Se abrirá el compositor de Mail del sistema."
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(methodHint)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancelar") { onClose() }
            // Botón directo al Mail del sistema (método D), siempre disponible como atajo.
            Button("Mail del sistema") { sendWithSystemMail() }
                .help("Abre el compositor de correo nativo con la imagen adjunta.")
            Button {
                Task { await primarySend() }
            } label: {
                if sending { ProgressView().controlSize(.small) }
                else { Text(sent ? "Enviado ✓" : "Enviar ✉") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sending || sent)
        }
        .padding(14)
    }

    /// Acción del botón principal: despacha según el método configurado.
    private func primarySend() async {
        if settings.mailMethod == .systemMail {
            sendWithSystemMail()
            return
        }
        await send()
    }

    /// Método D — abre el compositor nativo del sistema con la imagen adjunta.
    private func sendWithSystemMail() {
        let ok = SystemMailSender.compose(
            subject: subject,
            body: bodyText,
            recipients: split(to) + split(cc) + split(bcc),
            png: attachment,
            attachmentName: "captura.png"
        )
        if ok {
            // Hand-off al Mail del sistema: solo PRESENTAMOS el compositor nativo; no sabemos si el
            // usuario realmente envió. Cerramos sin marcar "enviado ✓" (sería engañoso).
            onClose()
        } else {
            errorText = "No se pudo abrir el Mail del sistema. ¿Tienes un cliente de correo configurado?"
        }
    }

    private func send() async {
        errorText = nil
        sending = true
        defer { sending = false }

        var draft = MailDraft(
            from: settings.mailFrom.trimmingCharacters(in: .whitespacesAndNewlines),
            to: split(to), cc: split(cc), bcc: split(bcc),
            subject: subject, body: bodyText, slug: slug,
            attachment: attachment,
            extraAttachments: extraAttachments,
            method: settings.mailMethod.rawValue
        )

        // Datos específicos por método antes de mandar al backend.
        switch settings.mailMethod {
        case .smtp:
            let pass = SecretStore.get(.smtp) ?? ""
            guard !settings.smtpHost.isEmpty, !settings.smtpUser.isEmpty, !pass.isEmpty else {
                errorText = "Faltan datos SMTP (host, usuario o contraseña). Configúralos en Preferencias → Email."
                return
            }
            let smtpFrom = settings.smtpFrom.isEmpty ? draft.from : settings.smtpFrom
            draft.smtp = SMTPConfig(host: settings.smtpHost, port: settings.smtpPort,
                                    user: settings.smtpUser, pass: pass, from: smtpFrom)
            // El remitente del correo coincide con el de SMTP.
            if !smtpFrom.isEmpty { draft.from = smtpFrom }
        case .oauth:
            do {
                draft.accessToken = try await GoogleOAuthClient.shared.freshAccessToken()
                // El remitente debe ser la cuenta conectada.
                let acct = settings.googleAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !acct.isEmpty { draft.from = acct }
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        case .systemMail:
            break   // systemMail no pasa por aquí (abre el compositor nativo)
        }

        do {
            try await MailClient.shared.send(draft)
            sent = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            onClose()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func split(_ s: String) -> [String] {
        s.replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Fila visual de un adjunto. Con `onRemove` muestra la ✕ (solo para los extras del usuario).
    private func attachmentRow(name: String, detail: String, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let onRemove {
                Button { onRemove() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    /// Abre un NSOpenPanel para elegir archivos y los agrega como adjuntos extra.
    private func addAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let maxBytes = 20 * 1024 * 1024   // límite por archivo: 20 MB
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if data.count > maxBytes {
                errorText = "“\(url.lastPathComponent)” supera 20 MB y no se adjuntó."
                continue
            }
            let mime = mimeType(for: url)
            extraAttachments.append(MailAttachment(name: url.lastPathComponent, mime: mime, data: data))
        }
    }

    private func mimeType(for url: URL) -> String {
        if let t = UTType(filenameExtension: url.pathExtension), let m = t.preferredMIMEType {
            return m
        }
        return "application/octet-stream"
    }

    private func byteLabel(_ n: Int) -> String {
        let kb = Double(n) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
