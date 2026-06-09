import Foundation

enum AppConfig {
    /// Produkcyjny backend Mindflow (Render). Mozna nadpisac bez rekompilacji:
    ///   defaults write com.mindflow.menubar apiBaseURL http://localhost:5125
    ///   defaults delete com.mindflow.menubar apiBaseURL   (powrot na prod)
    static var apiBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://mindflow-api-0506.onrender.com")!
    }

    // MARK: - Google OAuth (iOS client)
    //
    // Backend weryfikuje token Google sprawdzajac jego `aud`. Natywka loguje sie
    // wlasnym iOS OAuth clientem -> w API trzeba dodac jego client id do listy
    // akceptowanych audience (patrz README, sekcja "Backend").
    //
    // Po utworzeniu iOS OAuth client w Google Cloud wstaw obie wartosci:

    /// Pelny client id (typ iOS, bez secretu).
    static let googleClientID = "3208970947-fr2r82it05vq3t785crv0l5lm0u39vt7.apps.googleusercontent.com"

    /// Reversed client id = schemat URL callbacku (musi zgadzac sie z Info.plist).
    static let googleCallbackScheme = "com.googleusercontent.apps.3208970947-fr2r82it05vq3t785crv0l5lm0u39vt7"

    static var googleRedirectURI: String { "\(googleCallbackScheme):/oauthredirect" }

    /// Czy uzupelniono dane Google (false = przycisk logowania pokaze instrukcje).
    static var isGoogleConfigured: Bool {
        !googleClientID.hasPrefix("TODO") && !googleCallbackScheme.contains("TODO")
    }
}
