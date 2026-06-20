import SwiftUI
import AppKit

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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    audienceSegment
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
                        HStack(spacing: 10) {
                            Image(systemName: "paperclip").foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text("captura.png").font(.system(size: 13, weight: .medium))
                                Text("PNG · se adjunta al correo").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }

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

    private var footer: some View {
        HStack(spacing: 10) {
            Text("🔒 Se envía vía Klip (Gmail). Tu cuenta queda como remitente.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancelar") { onClose() }
            Button {
                Task { await send() }
            } label: {
                if sending { ProgressView().controlSize(.small) }
                else { Text(sent ? "Enviado ✓" : "Enviar ✉") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sending || sent)
        }
        .padding(14)
    }

    private func send() async {
        errorText = nil
        sending = true
        defer { sending = false }
        let draft = MailDraft(
            from: settings.mailFrom.trimmingCharacters(in: .whitespacesAndNewlines),
            to: split(to), cc: split(cc), bcc: split(bcc),
            subject: subject, body: bodyText, slug: slug,
            attachment: attachment
        )
        do {
            try await MailClient.shared.send(draft)
            sent = true
            // Cierra tras una breve confirmación.
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
}
