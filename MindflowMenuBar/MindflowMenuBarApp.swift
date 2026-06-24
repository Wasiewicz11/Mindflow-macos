import SwiftUI
import UserNotifications

@main
struct MindflowMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore()
    @StateObject private var agenda = AgendaViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(session)
                .environmentObject(agenda)
        } label: {
            MenuBarLabel(agenda: agenda, isLoggedIn: session.isLoggedIn)
                .task(id: session.isLoggedIn) {
                    if session.isLoggedIn { agenda.start(api: session.api) }
                    else { agenda.stop() }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        BlockNotifier().requestAuthorization()
    }

    // Pokazuj banner nawet gdy appka jest aktywna.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Przelacza miedzy ekranem logowania a agenda; pilnuje startu/stopu pollingu.
struct MenuBarContent: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var agenda: AgendaViewModel

    var body: some View {
        Group {
            if session.isLoggedIn {
                AgendaPopover()
            } else {
                LoginView()
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .onAppear {
            if session.isLoggedIn { agenda.start(api: session.api) }
        }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if loggedIn { agenda.start(api: session.api) }
            else { agenda.stop() }
        }
    }
}
