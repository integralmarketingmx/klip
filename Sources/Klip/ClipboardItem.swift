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

    // Señal de frecuencia (Consejo C7). firstSeenAt: cuándo se vio por primera vez este contenido
    // (createdAt se refresca al re-copiar; firstSeenAt no). copyCount: cuántas veces se ha copiado.
    var firstSeenAt: Date?        // items antiguos: nil (no se conocía la primera vez)
    var copyCount: Int            // items antiguos: 1 (ver init(from:))

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
         collection: String? = nil,
         firstSeenAt: Date? = nil,
         copyCount: Int = 1) {
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
        self.firstSeenAt = firstSeenAt ?? createdAt   // por defecto, la primera vez = creación
        self.copyCount = copyCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageFileName, preview, createdAt, pinned
        case sourceName, sourceBundleID, isRemote, isVoiceNote, isCredential
        case audioFileName, audioDuration, name, collection, firstSeenAt, copyCount
    }

    // Decode backward-compatible: el items.json antiguo no trae firstSeenAt ni copyCount → quedan
    // nil / 1 respectivamente (no se pierde nada al actualizar).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ClipboardKind.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        preview = try c.decode(String.self, forKey: .preview)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        isRemote = try c.decodeIfPresent(Bool.self, forKey: .isRemote)
        isVoiceNote = try c.decodeIfPresent(Bool.self, forKey: .isVoiceNote)
        isCredential = try c.decodeIfPresent(Bool.self, forKey: .isCredential)
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        audioDuration = try c.decodeIfPresent(Double.self, forKey: .audioDuration)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        collection = try c.decodeIfPresent(String.self, forKey: .collection)
        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt)   // antiguos: nil
        copyCount = try c.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1    // antiguos: 1
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
