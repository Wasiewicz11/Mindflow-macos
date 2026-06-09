import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var isSigningIn = false
    @Published var lastError: String?
    @Published private(set) var userEmail: String?

    let api: APIClient
    private let tokenStore = TokenStore()
    private let google = GoogleAuth()

    init() {
        let store = TokenStore()
        self.api = APIClient(tokenStore: store)
        self.isLoggedIn = store.accessToken != nil
        self.api.onUnauthorized = { [weak self] in
            self?.handleSessionExpired()
        }
    }

    func signIn() async {
        lastError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let idToken = try await google.signIn()
            try await api.loginWithGoogle(idToken: idToken)
            userEmail = Self.email(fromIDToken: idToken)
            isLoggedIn = true
        } catch GoogleAuthError.cancelled {
            // cisza – user sam zamknal okno
        } catch {
            lastError = error.localizedDescription
        }
    }

    func logout() {
        Task { await api.logout() }
        tokenStore.clear()
        userEmail = nil
        isLoggedIn = false
    }

    private func handleSessionExpired() {
        userEmail = nil
        isLoggedIn = false
        lastError = "Sesja wygasla. Zaloguj sie ponownie."
    }

    /// Wyciaga email z payloadu JWT (tylko do wyswietlenia "zalogowano jako").
    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["email"] as? String
    }
}
