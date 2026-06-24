import SwiftUI

struct AgendaPopover: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var agenda: AgendaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current = agenda.current {
                currentSection(current)
            } else {
                emptyCurrent
            }

            Divider().padding(.horizontal, 16).padding(.vertical, 12)

            nextSection

            footer
        }
        .padding(.vertical, 14)
    }

    // MARK: - TERAZ

    private func currentSection(_ item: AgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("TERAZ")
                Spacer()
                refreshButton
            }

            Text(item.title)
                .font(.title2.weight(.bold))
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Zostalo \(AgendaFormat.remaining(from: agenda.now, to: item.end))  ·  do \(AgendaFormat.clock(item.end))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let pomodoro = agenda.activePomodoro,
               let pomodoroTaskId = pomodoro.taskId,
               pomodoroTaskId == item.taskId {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(pomodoro.phase.label): zostalo \(AgendaFormat.remaining(seconds: pomodoro.secondsRemaining(at: agenda.now)))")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(pomodoro.phase.isBreak ? Color.green : Color.red)
            }

            AgendaProgressBar(value: agenda.progress)
        }
        .padding(.horizontal, 16)
    }

    private var emptyCurrent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("TERAZ")
                Spacer()
                refreshButton
            }
            Text("Brak aktywnego bloku")
                .font(.title3.weight(.semibold))
            Text("Nic nie jest teraz zaplanowane.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - NASTEPNE

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("NASTEPNE")

            if let next = agenda.next {
                HStack(alignment: .firstTextBaseline) {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(AgendaFormat.clock(next.start))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(AgendaFormat.relative(from: agenda.now, to: next.start))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nic wiecej dzisiaj")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Stopka

    private var footer: some View {
        HStack(spacing: 14) {
            if let email = session.userEmail {
                Text(email)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Wyloguj") { session.logout() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Zakoncz") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - Wspolne

    private var refreshButton: some View {
        Button {
            Task { await agenda.refresh() }
        } label: {
            Image(systemName: agenda.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

struct AgendaProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geo.size.width * value))
            }
        }
        .frame(height: 6)
    }
}
