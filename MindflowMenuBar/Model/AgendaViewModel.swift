import AppKit
import Foundation

@MainActor
final class AgendaViewModel: ObservableObject {
    @Published private(set) var items: [AgendaItem] = []
    @Published private(set) var now = Date()
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var api: APIClient?
    private let notifier = BlockNotifier()
    private var minuteTimer: Timer?
    private var pollTimer: Timer?

    // MARK: - Pochodne (jak useTodayCalendar na web)

    var current: AgendaItem? {
        items.first { $0.start <= now && now < $0.end }
    }

    var next: AgendaItem? {
        items.first { $0.start > now }
    }

    /// Minuty do konca aktualnego bloku (zaokraglone w gore). nil = brak aktywnego bloku.
    var minutesRemaining: Int? {
        guard let current else { return nil }
        return max(0, Int(ceil(current.end.timeIntervalSince(now) / 60)))
    }

    /// Postep aktualnego bloku 0...1.
    var progress: Double {
        guard let current else { return 0 }
        let total = current.end.timeIntervalSince(current.start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(current.start)
        return min(max(elapsed / total, 0), 1)
    }

    // MARK: - Cykl zycia

    func start(api: APIClient) {
        self.api = api
        startTimers()
        Task { await refresh() }
    }

    func stop() {
        minuteTimer?.invalidate(); minuteTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        api = nil
        items = []
        lastError = nil
        notifier.cancelAll()
    }

    func refresh() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let agenda = try await CalendarService(api: api).todayAgenda()
            items = agenda
            now = Date()
            lastError = nil
            notifier.schedule(items: agenda, now: now)
        } catch is CancellationError {
            // ignor
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Timery

    private func startTimers() {
        minuteTimer?.invalidate()
        pollTimer?.invalidate()

        minuteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}
