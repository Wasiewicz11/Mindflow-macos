import Foundation
import Security

/// Przechowuje access i refresh token.
///
/// DOMYSLNIE Keychain — poprawne dla produkcji (szyfrowane, systemowe).
/// W produkcji apka jest podpisana stabilnym Developer ID, wiec Keychain NIE pyta o zgode.
///
/// W devie z DARMOWYM kontem Apple podpis ("Sign to Run Locally") zmienia sie przy kazdym
/// buildzie -> Keychain pyta "Mindflow wants to use confidential information..." w kolko.
/// Na czas takiej iteracji mozna wlaczyc plikowy fallback (0600) BEZ rekompilacji:
///   defaults write com.mindflow.menubar useFileTokenStore -bool true    # dev: bez promptow
///   defaults delete com.mindflow.menubar useFileTokenStore              # powrot na Keychain
final class TokenStore {
    private let service = "com.mindflow.menubar"
    private let useFile = UserDefaults.standard.bool(forKey: "useFileTokenStore")
    private lazy var fileURL = Self.makeFileURL()
    private lazy var fileCache = Self.loadFile(fileURL)

    var accessToken: String? {
        get { read("accessToken") }
        set { write("accessToken", newValue) }
    }

    var refreshToken: String? {
        get { read("refreshToken") }
        set { write("refreshToken", newValue) }
    }

    func clear() {
        write("accessToken", nil)
        write("refreshToken", nil)
    }

    // MARK: - Wybor backendu

    private func read(_ account: String) -> String? {
        useFile ? fileCache[account] : keychainRead(account)
    }

    private func write(_ account: String, _ value: String?) {
        useFile ? fileWrite(account, value) : keychainWrite(account, value)
    }

    // MARK: - Keychain (prod)

    private func keychainRead(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private func keychainWrite(_ account: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrLabel as String] = "Mindflow"
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    // MARK: - Plik 0600 (dev fallback)

    private func fileWrite(_ account: String, _ value: String?) {
        if let value { fileCache[account] = value } else { fileCache.removeValue(forKey: account) }
        guard let data = try? JSONSerialization.data(withJSONObject: fileCache) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func makeFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Mindflow", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent("auth.json")
    }

    private static func loadFile(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return obj
    }
}
