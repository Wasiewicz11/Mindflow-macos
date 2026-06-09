import AppKit
import AuthenticationServices
import CryptoKit

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case missingCode
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Brak konfiguracji Google (uzupelnij AppConfig + Info.plist)."
        case .cancelled: return "Logowanie anulowane."
        case .missingCode: return "Google nie zwrocil kodu autoryzacji."
        case .missingIDToken: return "Google nie zwrocil tokenu id_token."
        }
    }
}

/// Logowanie Google natywnym sheetem (ASWebAuthenticationSession) z PKCE.
/// Zwraca `id_token` Google, ktory wysylamy do naszego /auth/login.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> String {
        guard AppConfig.isGoogleConfigured else { throw GoogleAuthError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        let callback = try await authenticate(url: comps.url!)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.missingCode
        }
        return try await exchange(code: code, verifier: verifier)
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.googleCallbackScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: GoogleAuthError.cancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    cont.resume(throwing: GoogleAuthError.cancelled)
                    return
                }
                cont.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        struct TokenResponse: Decodable { let id_token: String? }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data).id_token, !token.isEmpty else {
            throw GoogleAuthError.missingIDToken
        }
        return token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(hash))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
