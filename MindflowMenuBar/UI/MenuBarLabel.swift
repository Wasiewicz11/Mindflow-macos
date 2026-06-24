import AppKit
import SwiftUI

/// To, co widac na pasku menu. Cztery stany:
///  - aktywny blok                 -> sam czas "24 min" + delikatne podkreslenie (cos trwa)
///  - brak aktywnego, jest nastepny -> "za 24 min"
///  - nic juz dzisiaj              -> marka Mindle na zielono
///  - niezalogowany / przed 1. zaladowaniem -> marka Mindle (szablonowa, dopasowuje sie do paska)
struct MenuBarLabel: View {
    @ObservedObject var agenda: AgendaViewModel
    let isLoggedIn: Bool

    var body: some View {
        if !isLoggedIn || !agenda.hasLoaded {
            Image(nsImage: Self.markTemplate)
        } else if let minutes = agenda.pomodoroMinutesRemaining,
                  let pomodoro = agenda.activePomodoro {
            Image(nsImage: Self.timerStatusImage(
                agendaText: agendaStatusText,
                pomodoroMinutes: minutes,
                pomodoroColor: pomodoro.phase.isBreak ? .systemGreen : .systemRed
            ))
            .accessibilityLabel("\(agendaStatusText), Pomodoro \(minutes) minut")
        } else {
            agendaStatus
        }
    }

    private var agendaStatusText: String {
        if let minutes = agenda.minutesRemaining {
            return "\(minutes) min"
        }
        if let until = agenda.minutesUntilNext {
            return AgendaFormat.until(minutes: until)
        }
        return ""
    }

    @ViewBuilder
    private var agendaStatus: some View {
        if let minutes = agenda.minutesRemaining {
            Text("\(minutes) min")
        } else if let until = agenda.minutesUntilNext {
            Text(AgendaFormat.until(minutes: until))
        } else {
            Image(nsImage: Self.markGreen)
        }
    }

    // Szablonowa: pasek sam ja tonuje (czarna w jasnym, biala w ciemnym).
    private static let markTemplate = markImage(color: .black, template: true)
    // Zielona "wolne": niesablonowa, zeby kolor sie pokazal.
    private static let markGreen = markImage(color: .systemGreen, template: false)

    private static func timerStatusImage(
        agendaText: String,
        pomodoroMinutes: Int,
        pomodoroColor: NSColor
    ) -> NSImage {
        let fontSize = NSFont.systemFontSize
        let agendaAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let pomodoroAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: pomodoroColor,
        ]
        let agenda = NSAttributedString(string: agendaText, attributes: agendaAttributes)
        let pomodoro = NSAttributedString(
            string: agendaText.isEmpty ? "\(pomodoroMinutes) min" : "  \(pomodoroMinutes) min",
            attributes: pomodoroAttributes
        )
        let agendaSize = agenda.size()
        let pomodoroSize = pomodoro.size()
        let imageSize = NSSize(
            width: ceil(agendaSize.width + pomodoroSize.width),
            height: ceil(max(18, agendaSize.height, pomodoroSize.height))
        )
        let image = NSImage(size: imageSize, flipped: false) { _ in
            agenda.draw(at: NSPoint(x: 0, y: (imageSize.height - agendaSize.height) / 2))
            pomodoro.draw(at: NSPoint(
                x: agendaSize.width,
                y: (imageSize.height - pomodoroSize.height) / 2
            ))
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Rysuje marke Mindle (2 kolka + 2 slupki) w danym kolorze. Marka jest pionowo
    /// symetryczna (wszystko wokol y=60), wiec uklad wspolrzednych AppKit nie wymaga odbicia.
    private static func markImage(color: NSColor, template: Bool) -> NSImage {
        let dim: CGFloat = 18
        let image = NSImage(size: NSSize(width: dim, height: dim))
        image.lockFocus()
        if let cg = NSGraphicsContext.current?.cgContext {
            let s = dim / 120.0
            func sc(_ x: CGFloat) -> CGFloat { x * s }
            cg.setFillColor(color.cgColor)
            cg.addEllipse(in: CGRect(x: sc(20 - 8), y: sc(60 - 8), width: sc(16), height: sc(16)))
            cg.addPath(CGPath(roundedRect: CGRect(x: sc(38), y: sc(34), width: sc(18), height: sc(52)),
                              cornerWidth: sc(9), cornerHeight: sc(9), transform: nil))
            cg.addPath(CGPath(roundedRect: CGRect(x: sc(64), y: sc(22), width: sc(18), height: sc(76)),
                              cornerWidth: sc(9), cornerHeight: sc(9), transform: nil))
            cg.addEllipse(in: CGRect(x: sc(100 - 8), y: sc(60 - 8), width: sc(16), height: sc(16)))
            cg.fillPath()
        }
        image.unlockFocus()
        image.isTemplate = template
        return image
    }
}
