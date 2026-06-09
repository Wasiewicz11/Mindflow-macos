import Foundation

enum AgendaFormat {
    private static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "HH:mm" – godzina zegarowa (np. konca bloku).
    static func clock(_ date: Date) -> String {
        hourMinute.string(from: date)
    }

    /// Ile zostalo: "2:10" gdy >= 1h, inaczej "10 min".
    static func remaining(from now: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now)))
        let minutes = (seconds + 59) / 60      // zaokraglenie w gore
        if minutes >= 60 {
            return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        }
        return "\(minutes) min"
    }

    /// Odleglosc w czasie: "za 3 godz. 40 min", "za 12 min", "teraz".
    static func relative(from now: Date, to start: Date) -> String {
        let seconds = Int(start.timeIntervalSince(now))
        guard seconds > 0 else { return "teraz" }
        let minutes = seconds / 60
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "za \(h) godz. \(m) min" }
        if h > 0 { return "za \(h) godz." }
        return "za \(max(m, 1)) min"
    }
}
