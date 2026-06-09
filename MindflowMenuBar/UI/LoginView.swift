import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Mindflow")
                .font(.title3.weight(.bold))
            Text("Zaloguj sie, aby zobaczyc swoj dzien.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !AppConfig.isGoogleConfigured {
                Text("Najpierw uzupelnij dane Google w AppConfig.swift i Info.plist (patrz README).")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await session.signIn() }
            } label: {
                HStack(spacing: 8) {
                    if session.isSigningIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.crop.circle")
                    }
                    Text(session.isSigningIn ? "Logowanie..." : "Zaloguj sie przez Google")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(session.isSigningIn || !AppConfig.isGoogleConfigured)

            if let error = session.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Zakoncz") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
