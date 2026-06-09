import Foundation
import UserNotifications

/// Lokalne powiadomienia dla blokow: 10 min przed startem, na start, 15 min przed koncem.
/// Planujemy z wyprzedzeniem (trigger na konkretna date), wiec odpalaja sie nawet gdy
/// appka jest w tle.
struct BlockNotifier {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func schedule(items: [AgendaItem], now: Date) {
        // Przeplanowujemy od zera – prosto i odporne na zmiany w kalendarzu.
        center.removeAllPendingNotificationRequests()

        for item in items {
            add(id: "\(item.id):soon-start", fireAt: item.start.addingTimeInterval(-10 * 60), now: now,
                title: "Za 10 minut", body: item.title)
            add(id: "\(item.id):start", fireAt: item.start, now: now,
                title: "Teraz", body: item.title)
            add(id: "\(item.id):soon-end", fireAt: item.end.addingTimeInterval(-15 * 60), now: now,
                title: "Za 15 minut koniec", body: item.title)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private func add(id: String, fireAt: Date, now: Date, title: String, body: String) {
        let interval = fireAt.timeIntervalSince(now)
        guard interval > 1 else { return }   // tylko przyszle zdarzenia

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
