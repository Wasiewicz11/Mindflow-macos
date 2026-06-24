import Foundation

struct PomodoroService {
    let api: APIClient

    func currentSession() async throws -> ApiPomodoroSession? {
        try await api.getOptional("pomodoro/session")
    }
}
