import AppKit
import Foundation

@MainActor
final class PomodoroSoundNotifier {
    private struct ScheduledCompletion {
        let key: String
        let phase: PomodoroPhase
        let endsAt: Date
    }

    private let player = PomodoroSoundPlayer()
    private var scheduledCompletion: ScheduledCompletion?
    private var completionTask: Task<Void, Never>?
    private var playedKeys: Set<String> = []
    private let maximumLateness: TimeInterval = 30

    func update(session: ApiPomodoroSession?, now: Date = Date()) {
        let nextCompletion = completion(for: session)
        if scheduledCompletion?.key == nextCompletion?.key { return }

        if let previous = scheduledCompletion {
            completionTask?.cancel()
            completionTask = nil
            scheduledCompletion = nil
            playIfDue(previous, now: now)
        }

        guard let nextCompletion, nextCompletion.endsAt > now else { return }
        scheduledCompletion = nextCompletion
        let delay = nextCompletion.endsAt.timeIntervalSince(now)
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fireScheduledCompletion(key: nextCompletion.key)
        }
    }

    func stop() {
        completionTask?.cancel()
        completionTask = nil
        scheduledCompletion = nil
        playedKeys.removeAll()
        player.stop()
    }

    func previewFocusCompleted() {
        player.playFocusCompleted()
    }

    func previewBreakCompleted() {
        player.playBreakCompleted()
    }

    private func completion(for session: ApiPomodoroSession?) -> ScheduledCompletion? {
        guard let session,
              session.isRunning,
              let endsAt = session.endsAt.flatMap(ISODate.parse) else { return nil }
        return ScheduledCompletion(
            key: "\(session.id):\(session.phase.rawValue):\(session.endsAt ?? "")",
            phase: session.phase,
            endsAt: endsAt
        )
    }

    private func fireScheduledCompletion(key: String) {
        guard let completion = scheduledCompletion, completion.key == key else { return }
        completionTask = nil
        scheduledCompletion = nil
        playIfDue(completion, now: Date())
    }

    private func playIfDue(_ completion: ScheduledCompletion, now: Date) {
        let lateness = now.timeIntervalSince(completion.endsAt)
        guard lateness >= -0.5,
              lateness <= maximumLateness,
              playedKeys.insert(completion.key).inserted else { return }

        if completion.phase == .focus {
            player.playFocusCompleted()
        } else {
            player.playBreakCompleted()
        }

        if playedKeys.count > 128 {
            playedKeys = [completion.key]
        }
    }
}

@MainActor
final class PomodoroSoundPlayer {
    private lazy var focusBell = Self.makeBell(
        duration: 2.6,
        frequency: 659.25,
        decayRate: 0.9,
        fadeOutDuration: 0.3
    )
    private lazy var breakBellFirst = Self.makeBell(
        duration: 0.58,
        frequency: 783.99,
        decayRate: 4.5,
        fadeOutDuration: 0.1
    )
    private lazy var breakBellSecond = Self.makeBell(
        duration: 0.58,
        frequency: 783.99,
        decayRate: 4.5,
        fadeOutDuration: 0.1
    )
    private var secondBellTask: Task<Void, Never>?

    func playFocusCompleted() {
        stop()
        play(focusBell)
    }

    func playBreakCompleted() {
        stop()
        play(breakBellFirst)
        secondBellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(680))
            guard !Task.isCancelled else { return }
            self?.play(self?.breakBellSecond)
        }
    }

    func stop() {
        secondBellTask?.cancel()
        secondBellTask = nil
        focusBell?.stop()
        breakBellFirst?.stop()
        breakBellSecond?.stop()
    }

    private func play(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()
        sound.currentTime = 0
        sound.volume = 0.42
        sound.play()
    }

    private static func makeBell(
        duration: Double,
        frequency: Double,
        decayRate: Double,
        fadeOutDuration: Double
    ) -> NSSound? {
        let sampleRate = 44_100
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = [Int16]()
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let attack = min(1, time / 0.012)
            let decay = exp(-decayRate * time)
            let fadeOut = min(1, max(0, duration - time) / fadeOutDuration)
            let tone = sin(2 * .pi * frequency * time) * 0.66
                + sin(2 * .pi * frequency * 2.01 * time) * 0.23
                + sin(2 * .pi * frequency * 3.98 * time) * 0.11
            let normalized = max(-1, min(1, tone * attack * decay * fadeOut * 0.22))
            samples.append(Int16(normalized * Double(Int16.max)).littleEndian)
        }

        var pcm = Data()
        samples.withUnsafeBytes { pcm.append(contentsOf: $0) }

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &wav)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt32(sampleRate), to: &wav)
        append(UInt32(sampleRate * 2), to: &wav)
        append(UInt16(2), to: &wav)
        append(UInt16(16), to: &wav)
        wav.append(contentsOf: "data".utf8)
        append(UInt32(pcm.count), to: &wav)
        wav.append(pcm)

        return NSSound(data: wav)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
