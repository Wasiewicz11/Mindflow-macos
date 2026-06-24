import Foundation

struct AuthResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
}

enum APIError: LocalizedError {
    case noHTTP
    case unauthorized
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .noHTTP: return "Brak odpowiedzi z serwera."
        case .unauthorized: return "Sesja wygasla. Zaloguj sie ponownie."
        case .http(let code, _): return "Blad serwera (\(code))."
        case .decoding: return "Nie udalo sie odczytac danych."
        }
    }
}

final class APIClient {
    private let tokenStore: TokenStore
    private let session: URLSession

    /// Wolane gdy odswiezenie sesji nie powiodlo sie (UI ma wylogowac).
    var onUnauthorized: (() -> Void)?

    // Deduplikacja rownoleglych refreshy (rotacja refresh tokena nie znosi wyscigu).
    private var refreshTask: Task<Bool, Never>?
    private let refreshLock = NSLock()

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg)

        // Po restarcie apki cookie-jar jest pusty -> wstaw refresh token z Keychain.
        restoreRefreshCookie()
    }

    // MARK: - Public

    /// Wymienia token Google (id_token) na nasz accessToken + refresh token.
    @discardableResult
    func loginWithGoogle(idToken: String) async throws -> AuthResponse {
        var req = URLRequest(url: url(for: "auth/login"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.noHTTP }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        tokenStore.accessToken = auth.accessToken
        captureRefreshToken()
        return auth
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await sendAuthorized(path: path, method: "GET")
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func getOptional<T: Decodable>(_ path: String) async throws -> T? {
        let data = try await sendAuthorized(path: path, method: "GET")
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func listenForEvents(_ path: String, onEvent: @escaping @Sendable () async -> Void) async throws {
        try await listenForEvents(path, onEvent: onEvent, retryOn401: true)
    }

    func logout() async {
        _ = try? await sendAuthorized(path: "auth/logout", method: "POST", retryOn401: false)
        clearRefreshCookie()
    }

    // MARK: - Private

    private func url(for path: String) -> URL {
        URL(string: AppConfig.apiBaseURL.absoluteString + "/" + path)!
    }

    private func sendAuthorized(path: String, method: String, retryOn401: Bool = true) async throws -> Data {
        var req = URLRequest(url: url(for: path))
        req.httpMethod = method
        if method == "GET" {
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        }
        if let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.noHTTP }

        if http.statusCode == 401 && retryOn401 {
            if await refresh() {
                return try await sendAuthorized(path: path, method: method, retryOn401: false)
            }
            tokenStore.clear()
            clearRefreshCookie()
            DispatchQueue.main.async { [weak self] in self?.onUnauthorized?() }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func listenForEvents(
        _ path: String,
        onEvent: @escaping @Sendable () async -> Void,
        retryOn401: Bool
    ) async throws {
        var req = URLRequest(url: url(for: path))
        req.httpMethod = "GET"
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token = tokenStore.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.noHTTP }

        if http.statusCode == 401 && retryOn401 {
            guard await refresh() else {
                tokenStore.clear()
                clearRefreshCookie()
                DispatchQueue.main.async { [weak self] in self?.onUnauthorized?() }
                throw APIError.unauthorized
            }
            return try await listenForEvents(path, onEvent: onEvent, retryOn401: false)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, "Pomodoro event stream unavailable")
        }

        for try await line in bytes.lines where line.hasPrefix("data:") {
            try Task.checkCancellation()
            await onEvent()
        }
    }

    /// Tylko JEDEN refresh na raz; rownolegli wolajacy czekaja na ten sam wynik.
    private func refresh() async -> Bool {
        refreshLock.lock()
        if let existing = refreshTask {
            refreshLock.unlock()
            return await existing.value
        }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        refreshLock.unlock()

        let result = await task.value
        refreshLock.lock()
        refreshTask = nil
        refreshLock.unlock()
        return result
    }

    private func performRefresh() async -> Bool {
        var req = URLRequest(url: url(for: "auth/refresh"))
        req.httpMethod = "POST"
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            return false
        }
        tokenStore.accessToken = auth.accessToken
        captureRefreshToken()   // rotacja: backend wydal nowy refresh token
        return true
    }

    // MARK: - Refresh token: Keychain <-> cookie jar

    private var authURL: URL { url(for: "auth/login") }

    /// Po loginie/refreshu zapisz aktualny refresh token z cookie-jara do Keychain.
    private func captureRefreshToken() {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: authURL),
              let rt = cookies.first(where: { $0.name == "refresh_token" }) else { return }
        tokenStore.refreshToken = rt.value
    }

    /// Przy starcie apki odtworz cookie z Keychain (jar nie przezywa restartu).
    private func restoreRefreshCookie() {
        guard let value = tokenStore.refreshToken, let host = AppConfig.apiBaseURL.host else { return }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "refresh_token",
            .value: value,
            .domain: host,
            .path: "/auth",
            .expires: Date().addingTimeInterval(30 * 24 * 3600),
        ]
        if AppConfig.apiBaseURL.scheme == "https" { props[.secure] = "TRUE" }
        if let cookie = HTTPCookie(properties: props) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func clearRefreshCookie() {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: authURL) else { return }
        for cookie in cookies where cookie.name == "refresh_token" {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }
}
