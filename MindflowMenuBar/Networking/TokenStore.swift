import Foundation
import Security

/// Trzyma access i refresh token w Keychain (a nie w UserDefaults), bo to sekrety.
/// Refresh token trzymamy sami, zeby przezyl restart apki (cookie-jar URLSession nie przezywa).
final class TokenStore {
    private let service = "com.mindflow.menubar"

    var accessToken: String? {
        get { read(account: "accessToken") }
        set { write(account: "accessToken", value: newValue) }
    }

    var refreshToken: String? {
        get { read(account: "refreshToken") }
        set { write(account: "refreshToken", value: newValue) }
    }

    func clear() {
        write(account: "accessToken", value: nil)
        write(account: "refreshToken", value: nil)
    }

    private func read(account: String) -> String? {
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

    private func write(account: String, value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(insert as CFDictionary, nil)
    }
}
