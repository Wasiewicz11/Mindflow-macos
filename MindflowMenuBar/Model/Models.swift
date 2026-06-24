import Foundation

/// Blok kalendarza z API (/calendar/blocks). Bierzemy tylko to, czego potrzebuje pasek.
struct ApiCalendarBlock: Decodable {
    let id: String
    let taskId: String?
    let title: String?
    let startAt: String
    let durationMinutes: Int
}

/// Zadanie z API (/tasks). Potrzebne tylko do resolve tytulu bloku po taskId.
struct ApiTask: Decodable {
    let id: String
    let content: String
}

enum PomodoroPhase: String, Decodable {
    case focus = "Focus"
    case shortBreak = "ShortBreak"
    case longBreak = "LongBreak"

    var isBreak: Bool { self != .focus }

    var label: String {
        switch self {
        case .focus: return "Skupienie"
        case .shortBreak: return "Krotka przerwa"
        case .longBreak: return "Dluga przerwa"
        }
    }
}

struct ApiPomodoroSession: Decodable, Equatable {
    let id: String
    let taskId: String?
    let title: String
    let phase: PomodoroPhase
    let totalSeconds: Int
    let remainingSeconds: Int
    let isRunning: Bool
    let endsAt: String?
    let updatedAt: String

    func secondsRemaining(at now: Date) -> Int {
        if isRunning, let endsAt, let end = ISODate.parse(endsAt) {
            return max(0, Int(ceil(end.timeIntervalSince(now))))
        }
        return max(0, remainingSeconds)
    }
}

/// Znormalizowany element agendy uzywany przez UI.
struct AgendaItem: Identifiable, Equatable {
    let id: String
    let taskId: String?
    let title: String
    let start: Date
    let end: Date
}

enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
