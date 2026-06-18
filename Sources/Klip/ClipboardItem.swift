import Foundation

/// Tipo de elemento guardado en el historial del portapapeles.
enum ClipboardKind: String, Codable {
    case text
    case image
}

/// Un elemento del historial del portapapeles (texto o imagen).
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipboardKind
    var text: String?
    var imageFileName: String?
    var preview: String
    var createdAt: Date
    var pinned: Bool

    // Campos nuevos (Optional => el items.json antiguo decodifica sin error: quedan nil).
    var sourceName: String?       // "Google Chrome", "Notas"…
    var sourceBundleID: String?   // "com.google.Chrome"
    var isRemote: Bool?           // heurística: "otro dispositivo Apple"
    var isVoiceNote: Bool?        // transcripción de nota de voz
    var isCredential: Bool?       // marcado como credencial (token/API key)
    var audioFileName: String?    // nota de voz: archivo de audio original guardado (m4a) para reproducir
    var audioDuration: Double?    // duración del audio en segundos (para mostrar y la barra de progreso)
    var name: String?             // etiqueta puesta por el usuario (título buscable; aplica a cualquier elemento)
    var collection: String?       // nombre de la colección a la que pertenece (agrupar lotes de contexto)

    init(id: UUID = UUID(),
         kind: ClipboardKind,
         text: String? = nil,
         imageFileName: String? = nil,
         preview: String,
         createdAt: Date = Date(),
         pinned: Bool = false,
         sourceName: String? = nil,
         sourceBundleID: String? = nil,
         isRemote: Bool? = nil,
         isVoiceNote: Bool? = nil,
         isCredential: Bool? = nil,
         audioFileName: String? = nil,
         audioDuration: Double? = nil,
         name: String? = nil,
         collection: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.preview = preview
        self.createdAt = createdAt
        self.pinned = pinned
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.isRemote = isRemote
        self.isVoiceNote = isVoiceNote
        self.isCredential = isCredential
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.name = name
        self.collection = collection
    }

    // == completo: SwiftUI lo usa para decidir si re-renderiza una fila. Debe reflejar también
    // text/preview/audioFileName para que la nota de voz se actualice al pasar de "Transcribiendo…"
    // a su texto final (y al guardarse su audio).
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id && lhs.pinned == rhs.pinned && lhs.createdAt == rhs.createdAt
            && lhs.isCredential == rhs.isCredential && lhs.isVoiceNote == rhs.isVoiceNote
            && lhs.isRemote == rhs.isRemote
            && lhs.text == rhs.text && lhs.preview == rhs.preview
            && lhs.imageFileName == rhs.imageFileName && lhs.audioFileName == rhs.audioFileName
            && lhs.name == rhs.name && lhs.collection == rhs.collection
    }
}
