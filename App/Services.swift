import AVFoundation
import UserNotifications

enum Reminder {
    static let identifier = "daily-study"

    static func update(enabled: Bool, hour: Int, minute: Int) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        if !enabled {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return false
        }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
        let content = UNMutableNotificationContent()
        content.title = "وقت مرور واژه‌هاست"
        content.body = "چند دقیقه برای تمرین انگلیسی وقت بگذار."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }
}

enum TapCue: String {
    case open, reveal, rate, advance, correct, retry

    static let preferenceKey = "tapSoundsEnabled"
    static let enabledByDefault = true
    @MainActor func play() {
        let enabled = UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? Self.enabledByDefault
        guard enabled, !PronunciationService.shared.isPlaying else { return }
        TapSoundPlayer.shared.play(self)
    }
}

@MainActor final class TapSoundPlayer {
    static let shared = TapSoundPlayer()

    private let session = AVAudioSession.sharedInstance()
    private var players: [TapCue: AVAudioPlayer] = [:]
    private var activePlayer: AVAudioPlayer?
    private var finishTask: Task<Void, Never>?

    private init() {}

    func play(_ cue: TapCue) {
        guard let player = player(for: cue) else { return }
        if activePlayer == nil {
            do {
                try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
                try session.setActive(true)
            } catch { return }
        }

        finishTask?.cancel()
        activePlayer?.stop()
        activePlayer = player
        player.currentTime = 0
        guard player.play() else {
            stop()
            return
        }

        finishTask = Task {
            do {
                try await Task.sleep(for: .seconds(player.duration + 0.05))
                stop()
            } catch {
                // A new cue or pronunciation took over.
            }
        }
    }

    func stop() {
        finishTask?.cancel()
        finishTask = nil
        guard let player = activePlayer else { return }
        activePlayer = nil
        player.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func player(for cue: TapCue) -> AVAudioPlayer? {
        if let player = players[cue] { return player }
        guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Cues"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        players[cue] = player
        return player
    }
}
