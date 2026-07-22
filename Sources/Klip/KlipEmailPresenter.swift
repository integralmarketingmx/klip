import AppKit
import SwiftUI

/// Standalone entry point for the Klip-only "send capture by email" feature. Self-contained on
/// purpose: it presents EmailComposerView in its own window and keeps no ties to PanelController's
/// private state, so the feature drops onto any base (including Martin's upstream) without touching
/// the panel internals. Windows are kept alive in `liveWindows` and released on close.
enum KlipEmail {
    private static var liveWindows = Set<NSWindow>()

    /// Compose an email for a history item (image clips only — the PNG is the attachment).
    /// Best-effort upload first to get a correlation slug; the PNG is attached regardless.
    static func compose(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = Storage.shared.loadImage(fileName: fn),
              let png = Storage.shared.pngData(from: img) else { return }
        Task { @MainActor in
            var slug = ""
            if let link = try? await UploaderClient.shared.upload(pngData: png, ocrText: item.text) {
                slug = (link.lastPathComponent as NSString).deletingPathExtension
            }
            let subject = L10n.t("email.defaultSubject") + (item.name.map { " · \($0)" } ?? "")
            var body = [L10n.t("email.defaultBody")]
            if let ocr = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
                body.append("")
                body.append(L10n.t("email.ocrLabel"))
                body.append(ocr)
            }
            present(slug: slug, attachment: png, subject: subject, body: body.joined(separator: "\n"))
        }
    }

    /// Compose an email with an already-annotated image (e.g. the editor's Email button).
    static func composeImage(_ image: NSImage) {
        guard let png = Storage.shared.pngData(from: image) else { return }
        Task { @MainActor in
            var slug = ""
            if let link = try? await UploaderClient.shared.upload(pngData: png, ocrText: nil) {
                slug = (link.lastPathComponent as NSString).deletingPathExtension
            }
            present(slug: slug, attachment: png,
                    subject: L10n.t("email.defaultSubject"), body: L10n.t("email.defaultBody"))
        }
    }

    @MainActor
    private static func present(slug: String, attachment: Data?, subject: String, body: String) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let view = EmailComposerView(
            ownerEmail: "", slug: slug, attachment: attachment,
            initialSubject: subject, initialBody: body,
            onClose: { [weak w] in w?.close() }
        )
        w.title = L10n.t("email.win.title")
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        let closer = KlipWindowCloser { [weak w] in if let w { liveWindows.remove(w) } }
        w.delegate = closer
        objc_setAssociatedObject(w, &Self.closerKey, closer, .OBJC_ASSOCIATION_RETAIN)
        liveWindows.insert(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private static var closerKey: UInt8 = 0
}

/// Runs a cleanup block exactly once when its window closes, by any route (view button, red X, ⌘W).
final class KlipWindowCloser: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private var fired = false
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) {
        guard !fired else { return }
        fired = true
        onClose()
    }
}
