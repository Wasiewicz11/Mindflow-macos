import Foundation

struct PomodoroService {
    let api: APIClient

    func currentSession() async throws -> ApiPomodoroSession? {
        let cacheBuster = Int(Date().timeIntervalSince1970 * 1_000)
        return try await api.getOptional("pomodoro/session?_t=\(cacheBuster)")
    }
}
