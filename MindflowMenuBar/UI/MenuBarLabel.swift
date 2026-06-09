import SwiftUI

/// To, co widac na pasku: ikona zadania + minuty do konca aktualnego bloku.
struct MenuBarLabel: View {
    @ObservedObject var agenda: AgendaViewModel
    let isLoggedIn: Bool

    var body: some View {
        if isLoggedIn, let minutes = agenda.minutesRemaining {
            Text("\(Image(systemName: "checklist"))  \(minutes) min")
        } else {
            Image(systemName: "checklist")
        }
    }
}
