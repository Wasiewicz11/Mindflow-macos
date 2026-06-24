import Foundation

/// Pobiera dzisiejsze bloki i zamienia je na AgendaItem (z tytulem zadania).
struct CalendarService {
    let api: APIClient

    func todayAgenda() async throws -> [AgendaItem] {
        let key = Self.dayKey(Date())

        async let blocks: [ApiCalendarBlock] = api.get("calendar/blocks?from=\(key)&to=\(key)")
        async let tasks: [ApiTask] = api.get("tasks")

        let (loadedBlocks, loadedTasks) = try await (blocks, tasks)
        let titleByTaskId = Dictionary(loadedTasks.map { ($0.id, $0.content) }, uniquingKeysWith: { first, _ in first })

        return loadedBlocks.compactMap { block -> AgendaItem? in
            guard let start = ISODate.parse(block.startAt) else { return nil }
            let title = block.taskId.flatMap { titleByTaskId[$0] } ?? block.title ?? "Blok czasu"
            return AgendaItem(
                id: block.id,
                taskId: block.taskId,
                title: title,
                start: start,
                end: start.addingTimeInterval(TimeInterval(block.durationMinutes) * 60)
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
