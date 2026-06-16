import Foundation

/// Localización ligera (es/en) para la interfaz principal. El idioma se elige en Preferencias.
enum L10n {
    static var lang: String { Settings.shared.uiLanguage }

    static func t(_ key: String) -> String {
        let table = (lang == "en") ? en : es
        return table[key] ?? es[key] ?? key
    }

    private static let es: [String: String] = [
        "menu.show": "Mostrar historial",
        "menu.prefs": "Preferencias…",
        "menu.login": "Abrir al iniciar sesión",
        "menu.autopaste": "Activar pegado automático…",
        "menu.clear": "Borrar historial",
        "menu.quit": "Salir de Klip",
        "search": "Buscar…",
        "rec.record": "Grabar voz",
        "rec.stop": "Detener y transcribir",
        "rec.transcribing": "Transcribiendo…",
        "rec.setkey": "Configurar API key",
        "rec.stillthere": "¿Sigues ahí?",
        "rec.continue": "Continuar",
        "act.copyallmd": "Markdown",
        "act.upload": "Subir audio",
        "act.more": "Más acciones",
        "act.prefs": "Preferencias",
        "filter.all": "Todo",
        "filter.text": "Texto",
        "filter.image": "Imágenes",
        "filter.voice": "Voz",
        "filter.pinned": "Fijados",
        "filter.cred": "Credenciales",
        "act.guide": "Ver guía y atajos",
        "empty.title": "Tu historial está vacío",
        "empty.sub": "Copia texto o una captura y aparecerá aquí.",
        "empty.cred": "Sin credenciales guardadas",
        "empty.noresults": "Sin resultados",
        "row.copy": "Copiar / pegar",
        "row.save": "Guardar como archivo",
        "row.ocr": "Extraer texto (OCR)",
        "row.markdown": "Copiar como Markdown",
        "row.pin": "Fijar", "row.unpin": "Quitar fijado",
        "row.delete": "Eliminar",
        "row.reveal": "Mostrar / ocultar",
        "row.markcred": "Marcar como credencial",
        "row.unmarkcred": "Quitar de credenciales",
        "badge.remote": "Otro dispositivo"
    ]

    private static let en: [String: String] = [
        "menu.show": "Show history",
        "menu.prefs": "Preferences…",
        "menu.login": "Open at login",
        "menu.autopaste": "Enable auto-paste…",
        "menu.clear": "Clear history",
        "menu.quit": "Quit Klip",
        "search": "Search…",
        "rec.record": "Record voice",
        "rec.stop": "Stop and transcribe",
        "rec.transcribing": "Transcribing…",
        "rec.setkey": "Set API key",
        "rec.stillthere": "Still there?",
        "rec.continue": "Continue",
        "act.copyallmd": "Markdown",
        "act.upload": "Upload audio",
        "act.more": "More actions",
        "act.prefs": "Preferences",
        "filter.all": "All",
        "filter.text": "Text",
        "filter.image": "Images",
        "filter.voice": "Voice",
        "filter.pinned": "Pinned",
        "filter.cred": "Credentials",
        "act.guide": "Guide & shortcuts",
        "empty.title": "Your history is empty",
        "empty.sub": "Copy text or a screenshot and it'll show up here.",
        "empty.cred": "No saved credentials",
        "empty.noresults": "No results",
        "row.copy": "Copy / paste",
        "row.save": "Save as file",
        "row.ocr": "Extract text (OCR)",
        "row.markdown": "Copy as Markdown",
        "row.pin": "Pin", "row.unpin": "Unpin",
        "row.delete": "Delete",
        "row.reveal": "Show / hide",
        "row.markcred": "Mark as credential",
        "row.unmarkcred": "Remove from credentials",
        "badge.remote": "Other device"
    ]
}
