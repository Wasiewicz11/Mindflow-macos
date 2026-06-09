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

/// Znormalizowany element agendy uzywany przez UI.
struct AgendaItem: Identifiable, Equatable {
    let id: String
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
