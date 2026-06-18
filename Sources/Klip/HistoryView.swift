import SwiftUI
import AppKit

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, text, image, voice, credential, pinned
    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .all: "filter.all"; case .text: "filter.text"; case .image: "filter.image"
        case .voice: "filter.voice"; case .credential: "filter.cred"; case .pinned: "filter.pinned"
        }
    }
    var icon: String {
        switch self {
        case .all: "square.grid.2x2"; case .text: "doc.text"; case .image: "photo"
        case .voice: "waveform"; case .credential: "key.fill"; case .pinned: "pin.fill"
        }
    }
}

/// Interfaz del panel: encabezado, filtros por tipo, lista y guía.
struct HistoryView: View {
    @ObservedObject var manager: ClipboardManager
    @ObservedObject var selection: SelectionModel
    @ObservedObject var recorder: Recorder
    @ObservedObject var settings = Settings.shared
    var onPick: (ClipboardItem) -> Void
    var onSaveImage: (ClipboardItem) -> Void
    var onCopyMarkdown: (ClipboardItem) -> Void
    var onCopyAllMarkdown: () -> Void
    var onOpenPreferences: () -> Void
    var onUploadAudio: () -> Void
    var onVoiceRecord: () -> Void
    var onShowGuide: () -> Void
    var onRename: (ClipboardItem) -> Void
    var onRetryTranscription: (ClipboardItem) -> Void
    var onSaveAsFile: (ClipboardItem) -> Void
    var onCopyAsCode: (ClipboardItem) -> Void
    var onCaptureAnnotate: () -> Void
    var onCombinePDF: ([ClipboardItem]) -> Void
    var onExportZip: ([ClipboardItem]) -> Void
    var onAssignCollection: ([ClipboardItem]) -> Void

    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var filter: HistoryFilter = .all
    @State private var collectionFilter: String?
    @State private var selecting = false
    @State private var selectedBatch: Set<UUID> = []
    @State private var ocrResultID: UUID?
    @State private var ocrText = ""
    @State private var ocrRunning = false

    static let appLogo: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSApp.applicationIconImage
    }()

    private var sortedItems: [ClipboardItem] {
        manager.items.sorted { ($0.pinned ? 1 : 0, $0.createdAt) > ($1.pinned ? 1 : 0, $1.createdAt) }
    }

    private func matches(_ item: ClipboardItem, _ f: HistoryFilter) -> Bool {
        switch f {
        case .all: return true
        case .text: return item.kind == .text && item.isVoiceNote != true && item.isCredential != true
        case .image: return item.kind == .image
        case .voice: return item.isVoiceNote == true
        case .credential: return item.isCredential == true
        case .pinned: return item.pinned
        }
    }

    private var filtered: [ClipboardItem] {
        var base = sortedItems.filter { matches($0, filter) }
        if let cf = collectionFilter { base = base.filter { $0.collection == cf } }
        guard !search.isEmpty else { return base }
        let q = search.lowercased()
        base = base.filter {
            ($0.name ?? "").lowercased().contains(q)
            || ($0.text ?? "").lowercased().contains(q)
            || $0.preview.lowercased().contains(q)
        }
        return base
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !manager.items.isEmpty { filterRow }
            Divider()
            if filtered.isEmpty { emptyState } else { list }
            if selecting { batchBar }
        }
        .frame(minWidth: 420, minHeight: 460)
        .background(Color.clear)
        .onAppear { syncVisible(); searchFocused = true }
        .onChange(of: search) { _, _ in syncVisible() }
        .onChange(of: filter) { _, _ in syncVisible() }
        .onChange(of: collectionFilter) { _, _ in syncVisible() }
        .onChange(of: manager.items) { _, _ in
            // Si la colección filtrada dejó de existir (se borró/renombró su último elemento), soltar el
            // filtro: si no, la lista quedaría falsamente vacía sin chip visible para limpiarlo.
            if let cf = collectionFilter, !manager.collections.contains(cf) { collectionFilter = nil }
            // Quitar del lote los ids que ya no existen (p. ej. auto-recorte por maxItems al entrar clips
            // nuevos): mantiene el contador "N sel." sincronizado con lo que realmente se exportará.
            if !selectedBatch.isEmpty {
                let pruned = selectedBatch.intersection(Set(manager.items.map(\.id)))
                if pruned.count != selectedBatch.count { selectedBatch = pruned }
            }
            syncVisible()
        }
        .onChange(of: selecting) { _, newValue in selection.selecting = newValue }
        .onChange(of: selection.openToken) { _, _ in
            search = ""; filter = .all; collectionFilter = nil
            selecting = false; selectedBatch = []
            selection.updateVisible(sortedItems.map(\.id))
            selection.selectedIndex = sortedItems.isEmpty ? -1 : 0
            searchFocused = true
        }
        .onChange(of: selection.focusToken) { _, _ in searchFocused = true }   // re-foco sin limpiar búsqueda
    }

    private func syncVisible() { selection.updateVisible(filtered.map(\.id)) }

    // MARK: - Encabezado

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let logo = Self.appLogo {
                    Image(nsImage: logo).resizable().frame(width: 22, height: 22)
                }
                Text("Klip").font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                if recorder.transcribingCount > 0 {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("\(recorder.transcribingCount)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .help(L10n.t("rec.transcribing"))
                    .padding(.trailing, 2)
                }
                // Iconos de acción: tamaño uniforme y separación holgada para que no se encimen.
                HStack(spacing: 15) {
                    Button { toggleSelecting() } label: {
                        Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(selecting ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.borderless).help(L10n.t("sel.toggle"))
                    Button { onCaptureAnnotate() } label: { Image(systemName: "camera.viewfinder") }
                        .buttonStyle(.borderless).help(L10n.t("capture.annotate"))
                    Button { onVoiceRecord() } label: {
                        Image(systemName: recorder.state == .recording ? "mic.fill" : "mic")
                            .foregroundStyle(recorder.state == .recording ? .red : .primary)
                    }
                    .buttonStyle(.borderless).help(L10n.t("rec.record"))
                    Button { onUploadAudio() } label: { Image(systemName: "waveform.badge.plus") }
                        .buttonStyle(.borderless).help(L10n.t("act.upload"))
                    Menu {
                        Button { onCopyAllMarkdown() } label: { Label(L10n.t("act.copyallmd"), systemImage: "doc.richtext") }
                        Divider()
                        Button { onShowGuide() } label: { Label(L10n.t("act.guide"), systemImage: "questionmark.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("act.more"))
                    Button { onOpenPreferences() } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.borderless).help(L10n.t("act.prefs"))
                }
                .font(.system(size: 15))
                .imageScale(.medium)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.t("search"), text: $search)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                if !manager.items.isEmpty {
                    Text(filtered.count == manager.items.count ? "\(manager.items.count)"
                         : "\(filtered.count)/\(manager.items.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .padding(12)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HistoryFilter.allCases) { f in
                    chip(L10n.t(f.labelKey), icon: f.icon, selected: filter == f && collectionFilter == nil) {
                        filter = f; collectionFilter = nil
                    }
                }
                ForEach(manager.collections, id: \.self) { name in
                    chip(name, icon: "folder", selected: collectionFilter == name) {
                        let now = (collectionFilter == name ? nil : name)
                        collectionFilter = now
                        // Al activar una colección, soltar el filtro de tipo: si no, un `.image` (u otro)
                        // invisible seguiría ocultando elementos de la colección sin que ningún chip lo muestre.
                        if now != nil { filter = .all }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    private func chip(_ text: String, icon: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(text).font(.system(size: 11))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(selected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selección por lote (vibe coders)

    private func toggleSelecting() {
        selecting.toggle()
        if !selecting { selectedBatch = [] }
    }
    private func toggleCheck(_ id: UUID) {
        if selectedBatch.contains(id) { selectedBatch.remove(id) } else { selectedBatch.insert(id) }
    }
    // Orden VISIBLE (fijados primero, luego por fecha) — no el de inserción de manager.items — para que
    // el PDF/ZIP salga en el mismo orden en que el usuario ve y marca los elementos. Incluye elementos
    // seleccionados aunque un cambio de filtro los haya ocultado de `filtered`.
    private var batchItems: [ClipboardItem] { sortedItems.filter { selectedBatch.contains($0.id) } }

    private var batchBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedBatch.count) sel.").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            batchButton("doc.richtext", "PDF") { onCombinePDF(batchItems) }
            batchButton("doc.zipper", "ZIP") { onExportZip(batchItems) }
            batchButton("folder.badge.plus", L10n.t("sel.collection")) { onAssignCollection(batchItems) }
            Button(L10n.t("sel.done")) { selecting = false; selectedBatch = [] }
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func batchButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) { Image(systemName: icon); Text(label).font(.system(size: 11)) }
        }
        .controlSize(.small)
        .disabled(selectedBatch.isEmpty)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filtered) { item in
                        ItemRow(item: item,
                                isSelected: item.id == selection.selectedID,
                                resetToken: selection.openToken,
                                manager: manager,
                                onPick: onPick, onSaveImage: onSaveImage,
                                onCopyMarkdown: onCopyMarkdown, onOCR: { runOCR(item) },
                                onRename: onRename, onRetryTranscription: onRetryTranscription,
                                onSaveAsFile: onSaveAsFile, onCopyAsCode: onCopyAsCode,
                                searchTerm: search,
                                selecting: selecting, isChecked: selectedBatch.contains(item.id),
                                onToggleCheck: { toggleCheck(item.id) })
                            .id(item.id)
                        if ocrResultID == item.id { ocrBox }
                    }
                }
                .padding(8)
            }
            .onChange(of: selection.selectedID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(newID, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if manager.items.isEmpty && search.isEmpty && filter == .all {
                // Primer uso: bienvenida con los atajos reales (configurados) y un consejo.
                if let logo = Self.appLogo {
                    Image(nsImage: logo).resizable().frame(width: 46, height: 46).opacity(0.9)
                }
                Text(L10n.t("empty.title")).font(.system(size: 15, weight: .semibold))
                Text(L10n.t("empty.sub")).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    kbdHint(settings.combo.displayString, L10n.t("hint.open"))
                    kbdHint(settings.voiceCombo.displayString, L10n.t("rec.record"))
                }
                .padding(.top, 2)
                Text(L10n.t("empty.hover")).font(.system(size: 11)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: filter == .credential ? "key" : "magnifyingglass")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
                Text(filter == .credential ? L10n.t("empty.cred") : L10n.t("empty.noresults"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private func kbdHint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys).font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var ocrBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ocrRunning ? L10n.t("rec.transcribing") : "OCR:")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if !ocrRunning {
                Text(ocrText.isEmpty ? "—" : ocrText)
                    .font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
        .padding(.horizontal, 8).padding(.bottom, 4)
    }

    private func runOCR(_ item: ClipboardItem) {
        ocrResultID = item.id; ocrText = ""; ocrRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let text = manager.extractText(from: item) ?? ""
            DispatchQueue.main.async {
                ocrRunning = false; ocrText = text
                if !text.isEmpty { manager.setClipboardText(text) }
            }
        }
    }
}

/// Una fila del historial. Las imágenes se muestran en grande (imagen arriba, datos abajo).
struct ItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let resetToken: Int
    @ObservedObject var manager: ClipboardManager
    var onPick: (ClipboardItem) -> Void
    var onSaveImage: (ClipboardItem) -> Void
    var onCopyMarkdown: (ClipboardItem) -> Void
    var onOCR: () -> Void
    var onRename: (ClipboardItem) -> Void
    var onRetryTranscription: (ClipboardItem) -> Void
    var onSaveAsFile: (ClipboardItem) -> Void
    var onCopyAsCode: (ClipboardItem) -> Void
    var searchTerm: String = ""
    var selecting: Bool = false
    var isChecked: Bool = false
    var onToggleCheck: () -> Void = {}

    @State private var hovering = false
    @State private var revealed = false

    private var isCredential: Bool { item.isCredential == true }
    private var hasText: Bool { !(item.text?.isEmpty ?? true) }
    private var customName: String? {
        guard let nm = item.name, !nm.isEmpty else { return nil }
        return nm
    }

    /// Audio reproducible de una nota de voz (solo si el archivo sigue en disco).
    private var voiceAudioFile: String? {
        guard item.isVoiceNote == true, let af = item.audioFileName,
              Storage.shared.audioExists(fileName: af) else { return nil }
        return af
    }
    private var isTranscribing: Bool { item.preview == ClipboardManager.voiceTranscribing }

    /// Color si el texto del elemento es un hex (#RGB / #RRGGBB / #RRGGBBAA) → muestra una muestra.
    private var swatchColor: NSColor? {
        guard item.kind == .text, item.isVoiceNote != true, item.isCredential != true,
              let t = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return NSColor(klipHex: t)
    }

    /// Resalta las coincidencias de búsqueda en un texto (fondo amarillo).
    static func highlight(_ text: String, _ term: String) -> AttributedString {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return AttributedString(text) }
        var result = AttributedString()
        var idx = text.startIndex
        while idx < text.endIndex, let r = text.range(of: q, options: .caseInsensitive, range: idx..<text.endIndex) {
            result += AttributedString(String(text[idx..<r.lowerBound]))
            var m = AttributedString(String(text[r.lowerBound..<r.upperBound]))
            m.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.45)
            result += m
            idx = r.upperBound
        }
        result += AttributedString(String(text[idx...]))
        return result
    }

    /// URL si el elemento de texto es exactamente un enlace http(s) (para la acción "Abrir enlace").
    private var linkURL: URL? {
        guard item.kind == .text, item.isVoiceNote != true, item.isCredential != true,
              let t = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              t.hasPrefix("http://") || t.hasPrefix("https://"),
              !t.contains(" "), !t.contains("\n"),
              let u = URL(string: t), u.host != nil else { return nil }
        return u
    }

    private var displayedPreview: String {
        // El ojo alterna enmascarado/real (item.preview siempre está enmascarado para credenciales).
        if isCredential, let t = item.text { return revealed ? t : CredentialDetector.masked(t) }
        return item.preview.isEmpty ? "(vacío)" : item.preview
    }

    var body: some View {
        HStack(spacing: 8) {
            if selecting {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(isChecked ? Color.accentColor : .secondary)
                    .padding(.leading, 6)
            }
            Group {
                if item.kind == .image { imageCard } else { standardRow }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8)
            .fill((selecting && isChecked) || (!selecting && isSelected) ? Color.accentColor.opacity(0.20)
                  : (hovering ? Color.primary.opacity(0.07) : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected && !selecting ? Color.accentColor.opacity(0.6)
                    : (isCredential ? Color.yellow.opacity(0.4) : Color.clear), lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if selecting { onToggleCheck() } else { onPick(item) } }
        .onChange(of: resetToken) { _, _ in revealed = false }   // re-enmascarar al reabrir el panel
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fn = item.imageFileName, let img = Storage.shared.cachedImage(fileName: fn) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity).frame(height: 150)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                    Text({ let p = img.pixelDimensions; return "\(Int(p.width))×\(Int(p.height))" }())
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if let nm = customName {
                    Text(nm).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                HStack(spacing: 6) {
                    metadata
                    Spacer(minLength: 4)
                    if hovering && !selecting { actions } else if item.pinned { pinDot }
                }
            }
        }
        .padding(8)
    }

    private var standardRow: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                if let nm = customName {
                    Text(Self.highlight(nm, searchTerm)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(Self.highlight(displayedPreview, searchTerm))
                        .lineLimit(1).font(.system(size: 11, design: isCredential ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                } else {
                    Text(Self.highlight(displayedPreview, searchTerm))
                        .lineLimit(2).font(.system(size: 13, design: isCredential ? .monospaced : .default))
                }
                metadata
            }
            Spacer(minLength: 4)
            if hovering && !selecting { actions }
            else if isCredential { Image(systemName: "key.fill").foregroundStyle(.yellow).font(.system(size: 10)) }
            else if item.pinned { pinDot }
        }
        .padding(8)
    }

    private var pinDot: some View { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.system(size: 10)) }

    @ViewBuilder private var thumbnail: some View {
        if isCredential {
            Image(systemName: "key.fill").font(.system(size: 18))
                .frame(width: 46, height: 46).foregroundStyle(.yellow)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.14)))
        } else if item.isVoiceNote == true {
            // Sin texto (transcribiendo/fallida) + audio: botón ▶, coherente con el tap de la fila (reproduce).
            // Con texto: ícono estático (el tap de la fila pega el texto; reproducir está en las acciones).
            if !hasText, let af = voiceAudioFile {
                VoicePlayButton(fileName: af, large: true)
            } else {
                Image(systemName: "waveform").font(.system(size: 20))
                    .frame(width: 46, height: 46).foregroundStyle(.purple)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.12)))
            }
        } else if let c = swatchColor {
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: c))
                .frame(width: 46, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
        } else {
            Image(systemName: "doc.text").font(.system(size: 18))
                .frame(width: 46, height: 46).foregroundStyle(.secondary)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(Self.timeLabel(item.createdAt)).font(.system(size: 10)).foregroundStyle(.secondary)
            if let af = voiceAudioFile {
                VoicePlaybackInfo(fileName: af, duration: item.audioDuration)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if item.isVoiceNote == true {
                if let af = voiceAudioFile {
                    if hasText { VoicePlayButton(fileName: af, large: false) }
                    else if !isTranscribing {   // nota fallida con audio: ofrecer reintentar
                        iconButton("arrow.clockwise", L10n.t("voice.retry")) { onRetryTranscription(item) }
                    }
                    iconButton("folder", L10n.t("voice.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.shared.audioURL(for: af)])
                    }
                }
                if hasText {
                    iconButton("doc.on.doc", L10n.t("row.copy")) { onPick(item) }
                    iconButton("doc.richtext", L10n.t("row.markdown")) { onCopyMarkdown(item) }
                }
            } else if item.kind == .image {
                iconButton("doc.on.doc", L10n.t("row.copy")) { onPick(item) }
                if let fn = item.imageFileName {
                    iconButton("arrow.up.left.and.arrow.down.right", L10n.t("row.viewbig")) {
                        NSWorkspace.shared.open(Storage.shared.imageURL(for: fn))
                    }
                }
                iconButton("square.and.arrow.down", L10n.t("row.save")) { onSaveImage(item) }
                iconButton("text.viewfinder", L10n.t("row.ocr")) { onOCR() }
            } else if isCredential {
                iconButton("doc.on.doc", L10n.t("row.copy")) { onPick(item) }
                iconButton(revealed ? "eye.slash" : "eye", L10n.t("row.reveal")) { revealed.toggle() }
                iconButton("key.slash", L10n.t("row.unmarkcred")) { manager.toggleCredential(item) }
            } else {
                iconButton("doc.on.doc", L10n.t("row.copy")) { onPick(item) }
                if let u = linkURL {
                    iconButton("arrow.up.right.square", L10n.t("row.openlink")) { NSWorkspace.shared.open(u) }
                }
                Menu {
                    Button { onCopyAsCode(item) } label: { Label(L10n.t("row.code"), systemImage: "chevron.left.forwardslash.chevron.right") }
                    Button { onCopyMarkdown(item) } label: { Label(L10n.t("row.markdown"), systemImage: "doc.richtext") }
                    Button { onSaveAsFile(item) } label: { Label(L10n.t("row.savefile"), systemImage: "square.and.arrow.down") }
                    Divider()
                    Button { manager.toggleCredential(item) } label: { Label(L10n.t("row.markcred"), systemImage: "key") }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("act.more"))
            }
            iconButton("pencil", L10n.t("row.rename")) { onRename(item) }
            iconButton(item.pinned ? "pin.slash" : "pin", L10n.t(item.pinned ? "row.unpin" : "row.pin")) {
                manager.togglePin(item)
            }
            iconButton("trash", L10n.t("row.delete")) { manager.delete(item) }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)) }
            .buttonStyle(.borderless).help(help)
    }

    /// Etiqueta de fecha legible: "Hoy · 10:43", "Ayer · 10:43" o "martes 04 de julio · 10:43".
    static func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let en = Settings.shared.uiLanguage == "en"
        let time = df(en ? "h:mm a" : "HH:mm", en).string(from: date)
        if cal.isDateInToday(date)     { return "\(L10n.t("date.today")) · \(time)" }
        if cal.isDateInYesterday(date) { return "\(L10n.t("date.yesterday")) · \(time)" }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: Date())
        let fmt = en ? (sameYear ? "EEEE, MMM d" : "EEEE, MMM d, yyyy")
                     : (sameYear ? "EEEE dd 'de' MMMM" : "EEEE dd 'de' MMMM yyyy")
        return "\(df(fmt, en).string(from: date)) · \(time)"
    }

    /// DateFormatters cacheados por (idioma, formato) — evita recrearlos en cada render.
    private static var dfCache: [String: DateFormatter] = [:]
    private static func df(_ format: String, _ en: Bool) -> DateFormatter {
        let cacheKey = "\(en ? "en" : "es")|\(format)"
        if let f = dfCache[cacheKey] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: en ? "en_US" : "es_ES")
        f.dateFormat = format
        dfCache[cacheKey] = f
        return f
    }
}

extension NSColor {
    /// Parsea un color hex (#RGB, #RRGGBB, #RRGGBBAA, con o sin #). nil si no es un hex válido.
    convenience init?(klipHex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard [3, 6, 8].contains(s.count), s.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        func byte(_ sub: Substring) -> CGFloat { CGFloat(Int(sub, radix: 16) ?? 0) / 255.0 }
        let chars = Array(s)
        let r, g, b: CGFloat
        var a: CGFloat = 1
        if s.count == 3 {
            r = byte(Substring(String(repeating: chars[0], count: 2)))
            g = byte(Substring(String(repeating: chars[1], count: 2)))
            b = byte(Substring(String(repeating: chars[2], count: 2)))
        } else {
            r = byte(s.prefix(2))
            g = byte(s.dropFirst(2).prefix(2))
            b = byte(s.dropFirst(4).prefix(2))
            if s.count == 8 { a = byte(s.dropFirst(6).prefix(2)) }
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// Formatea segundos como m:ss (0:14, 1:05…) o h:mm:ss para audios largos subidos (1:02:03).
func mmss(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded()))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Muestra la duración del audio y, mientras suena ESE archivo, el tiempo transcurrido + barra de progreso.
/// Observa AudioPlayer.shared: todas las VoicePlaybackInfo visibles se reevalúan ~5/s mientras algo suena
/// (aceptable porque el body es trivial y LazyVStack limita a las filas en pantalla).
struct VoicePlaybackInfo: View {
    let fileName: String
    let duration: Double?
    @ObservedObject private var audio = AudioPlayer.shared

    var body: some View {
        if audio.isPlaying(fileName) {
            let total = audio.total > 0 ? audio.total : (duration ?? 0)
            HStack(spacing: 5) {
                Text("\(mmss(audio.elapsed)) / \(mmss(total))").monospacedDigit()
                ProgressView(value: total > 0 ? min(1, audio.elapsed / total) : 0)
                    .frame(width: 54).controlSize(.mini)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        } else if let d = duration {
            Text(mmss(d)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// Botón ▶/⏹ de una nota de voz. Observa AudioPlayer.shared (igual que VoicePlaybackInfo): mantiene la
/// observación fuera de ItemRow para no recalcular la fila entera en cada cambio de reproducción.
struct VoicePlayButton: View {
    let fileName: String
    var large: Bool = false
    @ObservedObject private var audio = AudioPlayer.shared

    var body: some View {
        let icon = audio.isPlaying(fileName) ? "stop.fill" : "play.fill"
        Group {
            if large {
                Button { AudioPlayer.shared.toggle(fileName: fileName) } label: {
                    Image(systemName: icon).font(.system(size: 18))
                        .frame(width: 46, height: 46).foregroundStyle(.purple)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else {
                Button { AudioPlayer.shared.toggle(fileName: fileName) } label: {
                    Image(systemName: icon).font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
        }
        .help(L10n.t("voice.play"))
    }
}
