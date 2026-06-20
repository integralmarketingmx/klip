import Foundation
import AppKit
import CryptoKit

/// Método B — "Iniciar sesión con Google": flujo OAuth 2.0 de escritorio (loopback)
/// con PKCE. Abre el navegador a la pantalla de consentimiento de Google (scope
/// `gmail.send`), recibe el `code` en un servidor local `http://127.0.0.1:<puerto>/`,
/// lo intercambia por tokens y guarda el **refresh token CIFRADO** en `SecretStore`
/// (`.googleOAuth`). El Client ID/secret salen de Settings (`googleClientId` /
/// `googleClientSecret`), configurables y vacíos por default.
///
/// Camino de envío elegido (documentado): el app renueva el **access token** con el
/// refresh token y lo manda al backend `POST /send` con `method:"oauth"` +
/// `accessToken`. El backend envía vía Gmail API con ESE token (sin DWD). Se eligió
/// pasar por el backend para reutilizar `buildMIME`/`/send` (una sola ruta) en vez
/// de duplicar el armado MIME en Swift.
enum GoogleOAuthError: Error, LocalizedError {
    case missingClient            // faltan Client ID/secret en Preferencias
    case notConnected             // no hay refresh token guardado (usuario no conectó)
    case server(String)           // error del servidor local de loopback
    case denied(String)           // el usuario negó el consentimiento / error de Google
    case token(String)            // fallo intercambiando/renovando tokens
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingClient: return "Configura el Client ID y Client Secret de Google en Preferencias."
        case .notConnected:  return "No hay una cuenta de Google conectada. Pulsa \"Conectar con Google\"."
        case .server(let m): return "No se pudo iniciar el servidor local de OAuth: \(m)"
        case .denied(let m): return "Google rechazó o canceló el acceso: \(m)"
        case .token(let m):  return "Error obteniendo el token de Google: \(m)"
        case .transport(let e): return "Error de red con Google: \(e.localizedDescription)"
        }
    }
}

final class GoogleOAuthClient {
    static let shared = GoogleOAuthClient()
    private init() {}

    private let authBase  = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL  = "https://oauth2.googleapis.com/token"
    private let scope     = "https://www.googleapis.com/auth/gmail.send"
    // Scope extra solo para leer el email de la cuenta conectada (estado de UI).
    private let emailScope = "https://www.googleapis.com/auth/userinfo.email"

    /// True si hay un refresh token guardado (cuenta conectada).
    var isConnected: Bool { SecretStore.hasKey(.googleOAuth) }

    // MARK: - Conectar (consentimiento + intercambio de code)

    /// Lanza el flujo completo: abre el navegador, espera el `code` en loopback,
    /// lo intercambia y guarda el refresh token cifrado. Devuelve el email conectado.
    @MainActor
    func connect() async throws -> String {
        let clientId = Settings.shared.googleClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = Settings.shared.googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw GoogleOAuthError.missingClient }

        // PKCE.
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafe(24)

        // Servidor de loopback en un puerto libre.
        let listener = try LoopbackServer()
        let redirectURI = "http://127.0.0.1:\(listener.port)/"

        guard var comps = URLComponents(string: authBase) else {
            throw GoogleOAuthError.denied("URL de autorización inválida")
        }
        comps.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "\(scope) \(emailScope)"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        guard let authURL = comps.url else { throw GoogleOAuthError.denied("URL de consentimiento inválida") }

        NSWorkspace.shared.open(authURL)

        // Espera el redirect con el code (o error).
        let params = try await listener.waitForCallback()
        if let err = params["error"] { throw GoogleOAuthError.denied(err) }
        guard params["state"] == state else { throw GoogleOAuthError.denied("state no coincide (posible CSRF)") }
        guard let code = params["code"] else { throw GoogleOAuthError.denied("no se recibió el código") }

        // Intercambio code -> tokens.
        let tokens = try await exchangeCode(code, verifier: verifier,
                                            clientId: clientId, clientSecret: clientSecret,
                                            redirectURI: redirectURI)
        guard let refresh = tokens.refreshToken else {
            throw GoogleOAuthError.token("Google no devolvió refresh token (revoca el acceso y reintenta con prompt=consent)")
        }
        _ = try SecretStore.set(refresh, .googleOAuth)

        // Email de la cuenta (best-effort) para mostrar el estado "conectado como X".
        let email = (try? await fetchEmail(accessToken: tokens.accessToken)) ?? ""
        await MainActor.run { Settings.shared.googleAccountEmail = email }
        return email
    }

    /// Desconecta: borra el refresh token y el email guardado.
    func disconnect() {
        SecretStore.delete(.googleOAuth)
        Settings.shared.googleAccountEmail = ""
    }

    // MARK: - Access token (renovación con el refresh token)

    /// Devuelve un access token fresco con el refresh token guardado. Lanza si no hay cuenta.
    func freshAccessToken() async throws -> String {
        guard let refresh = SecretStore.get(.googleOAuth) else { throw GoogleOAuthError.notConnected }
        let clientId = Settings.shared.googleClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = Settings.shared.googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw GoogleOAuthError.missingClient }

        guard let tURL = URL(string: tokenURL) else { throw GoogleOAuthError.token("URL de token inválida") }
        var req = URLRequest(url: tURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody([
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        let (data, resp) = try await dataTask(req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleOAuthError.token(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        let parsed = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let at = parsed.accessToken else { throw GoogleOAuthError.token("respuesta sin access_token") }
        return at
    }

    // MARK: - Helpers privados

    private struct Tokens { var accessToken: String?; var refreshToken: String? }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private func exchangeCode(_ code: String, verifier: String,
                              clientId: String, clientSecret: String,
                              redirectURI: String) async throws -> Tokens {
        guard let tURL = URL(string: tokenURL) else { throw GoogleOAuthError.token("URL de token inválida") }
        var req = URLRequest(url: tURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody([
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
        let (data, resp) = try await dataTask(req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleOAuthError.token(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        let parsed = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Tokens(accessToken: parsed.accessToken, refreshToken: parsed.refreshToken)
    }

    private func fetchEmail(accessToken: String?) async throws -> String {
        guard let at = accessToken else { return "" }
        guard let infoURL = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return "" }
        var req = URLRequest(url: infoURL)
        req.setValue("Bearer \(at)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await dataTask(req)
        struct Info: Decodable { let email: String? }
        return (try? JSONDecoder().decode(Info.self, from: data))?.email ?? ""
    }

    /// Wrapper async de URLSession compatible con versiones donde `data(for:)` no esté disponible.
    private func dataTask(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: req) }
        catch { throw GoogleOAuthError.transport(error) }
    }

    private static func formBody(_ dict: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = dict.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Servidor de loopback mínimo (acepta una sola conexión y devuelve el redirect)

/// Servidor TCP mínimo basado en POSIX sockets: escucha en 127.0.0.1:<puerto libre>,
/// acepta la primera petición HTTP del redirect de Google, extrae los query params y
/// responde una página de "puedes cerrar esta pestaña". Se usa una sola vez por flujo.
private final class LoopbackServer {
    let port: UInt16
    private let fd: Int32

    init() throws {
        // Trabajamos con una copia local del descriptor: usar `self.fd` dentro de los
        // closures de withUnsafePointer durante init capturaría `self` antes de que
        // todos sus miembros (port) estén inicializados.
        let sockFD = socket(AF_INET, SOCK_STREAM, 0)
        guard sockFD >= 0 else { throw GoogleOAuthError.server("socket() falló") }
        self.fd = sockFD
        var yes: Int32 = 1
        setsockopt(sockFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0   // puerto efímero asignado por el kernel

        let bindOK = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sockFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else { close(sockFD); throw GoogleOAuthError.server("bind() falló") }
        guard listen(sockFD, 1) == 0 else { close(sockFD); throw GoogleOAuthError.server("listen() falló") }

        // Leer el puerto efectivo asignado.
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameOK = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sockFD, $0, &len)
            }
        }
        guard nameOK == 0 else { close(sockFD); throw GoogleOAuthError.server("getsockname() falló") }
        self.port = UInt16(bigEndian: bound.sin_port)
    }

    /// Espera (en background) a que llegue el redirect y devuelve sus query params.
    func waitForCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async { [fd] in
                defer { close(fd) }
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    cont.resume(throwing: GoogleOAuthError.server("accept() falló")); return
                }
                defer { close(client) }

                // Leer la línea de petición (suficiente para el redirect GET / ?code=...).
                var buf = [UInt8](repeating: 0, count: 8192)
                let n = read(client, &buf, buf.count)
                let request = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""

                // Extraer la ruta de la primera línea: "GET /?code=...&state=... HTTP/1.1".
                var params: [String: String] = [:]
                if let firstLine = request.split(separator: "\r\n").first {
                    let parts = firstLine.split(separator: " ")
                    if parts.count >= 2, let comps = URLComponents(string: "http://127.0.0.1" + parts[1]) {
                        for item in comps.queryItems ?? [] {
                            params[item.name] = item.value ?? ""
                        }
                    }
                }

                // Responder una página simple.
                let html = """
                <!doctype html><html lang="es"><head><meta charset="utf-8">
                <title>Klip</title></head><body style="font-family:-apple-system,sans-serif;text-align:center;padding:48px">
                <h2>✅ Cuenta de Google conectada</h2>
                <p>Ya puedes volver a Klip y cerrar esta pestaña.</p></body></html>
                """
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
                _ = resp.withCString { write(client, $0, strlen($0)) }

                cont.resume(returning: params)
            }
        }
    }
}
