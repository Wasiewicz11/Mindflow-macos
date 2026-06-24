import AppKit
import Foundation

@MainActor
final class AgendaViewModel: ObservableObject {
    @Published private(set) var items: [AgendaItem] = []
    @Published private(set) var now = Date()
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    /// false dopoki nie zaladujemy dnia choc raz (chroni przed falszywym "zielonym" stanem).
    @Published private(set) var hasLoaded = false
    @Published private(set) var pomodoro: ApiPomodoroSession?

    private var api: APIClient?
    private let notifier = BlockNotifier()
    private var clockTimer: Timer?
    private var agendaPollTimer: Timer?
    private var pomodoroPollTimer: Timer?
    private var activeObserver: NSObjectProtocol?
    private var isRefreshingPomodoro = false
    private var pomodoroEventsTask: Task<Void, Never>?

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

    /// Minuty do startu nastepnego bloku. nil = nic wiecej dzisiaj.
    var minutesUntilNext: Int? {
        guard let next else { return nil }
        return max(0, Int(ceil(next.start.timeIntervalSince(now) / 60)))
    }

    /// Postep aktualnego bloku 0...1.
    var progress: Double {
        guard let current else { return 0 }
        let total = current.end.timeIntervalSince(current.start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(current.start)
        return min(max(elapsed / total, 0), 1)
    }

    var activePomodoro: ApiPomodoroSession? {
        guard let pomodoro, pomodoro.secondsRemaining(at: now) > 0 else { return nil }
        return pomodoro
    }

    var pomodoroMinutesRemaining: Int? {
        guard let activePomodoro else { return nil }
        return max(1, Int(ceil(Double(activePomodoro.secondsRemaining(at: now)) / 60)))
    }

    // MARK: - Cykl zycia

    func start(api: APIClient) {
        self.api = api
        startTimers()
        startPomodoroEvents(api: api)
        Task { await refresh() }
    }

    func stop() {
        clockTimer?.invalidate(); clockTimer = nil
        agendaPollTimer?.invalidate(); agendaPollTimer = nil
        pomodoroPollTimer?.invalidate(); pomodoroPollTimer = nil
        pomodoroEventsTask?.cancel(); pomodoroEventsTask = nil
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
        api = nil
        items = []
        pomodoro = nil
        isRefreshingPomodoro = false
        lastError = nil
        hasLoaded = false
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
            hasLoaded = true
            notifier.schedule(items: agenda, now: now)
        } catch is CancellationError {
            // ignor
        } catch {
            lastError = error.localizedDescription
        }
        await refreshPomodoro()
    }

    func refreshPomodoro() async {
        guard let api, !isRefreshingPomodoro else { return }
        isRefreshingPomodoro = true
        defer { isRefreshingPomodoro = false }
        do {
            let session = try await PomodoroService(api: api).currentSession()
            guard self.api === api else { return }
            pomodoro = session
            now = Date()
        } catch is CancellationError {
            // ignor
        } catch {
            // Agenda nadal dziala, gdy opcjonalny endpoint Pomodoro jest chwilowo niedostepny.
        }
    }

    // MARK: - Timery

    private func startTimers() {
        clockTimer?.invalidate()
        agendaPollTimer?.invalidate()
        pomodoroPollTimer?.invalidate()

        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        agendaPollTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        pomodoroPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshPomodoro() }
        }

        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func startPomodoroEvents(api: APIClient) {
        pomodoroEventsTask?.cancel()
        pomodoroEventsTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await api.listenForEvents("pomodoro/events") { [weak self] in
                        await self?.refreshPomodoro()
                    }
                    try? await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }
}
