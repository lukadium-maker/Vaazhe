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

@MainActor enum PlaybackAudioSession {
    private static var transition: Task<Void, Never>?

    static func activate(mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions,
                         completion: @escaping @MainActor (Bool) -> Void) {
        let previous = transition
        transition = Task {
            await previous?.value
            let succeeded = await Task.detached {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playback, mode: mode, options: options)
                    if #available(iOS 27, *) {
                        return try await session.activate(options: [])
                    }
                    try session.setActive(true)
                    return true
                } catch {
                    return false
                }
            }.value
            completion(succeeded)
        }
    }

    static func performPlayerOperation<Result: Sendable>(
        _ operation: @escaping @Sendable () -> Result,
        completion: @escaping @MainActor (Result) -> Void = { _ in }
    ) {
        let previous = transition
        transition = Task {
            await previous?.value
            let result = await Task.detached { operation() }.value
            completion(result)
        }
    }

    static func deactivate() {
        let previous = transition
        transition = Task {
            await previous?.value
            await Task.detached {
                let session = AVAudioSession.sharedInstance()
                if #available(iOS 27, *) {
                    _ = try? await session.deactivate(options: .notifyOthersOnDeactivation)
                } else {
                    try? session.setActive(false, options: .notifyOthersOnDeactivation)
                }
            }.value
        }
    }
}

@MainActor final class TapSoundPlayer {
    static let shared = TapSoundPlayer()

    private var players: [TapCue: AVAudioPlayer] = [:]
    private var activePlayer: AVAudioPlayer?
    private var pendingActivation: UUID?
    private var playbackRequest: UUID?
    private var finishTask: Task<Void, Never>?

    private init() {}

    func play(_ cue: TapCue) {
        guard let player = player(for: cue) else { return }
        finishTask?.cancel()
        playbackRequest = nil
        if let activePlayer {
            PlaybackAudioSession.performPlayerOperation { activePlayer.stop() }
        }
        if activePlayer == nil {
            let request = UUID()
            pendingActivation = request
            activePlayer = player
            PlaybackAudioSession.activate(mode: .default, options: .mixWithOthers) { [weak self] succeeded in
                guard let self, pendingActivation == request else { return }
                pendingActivation = nil
                guard succeeded, let activePlayer else {
                    stop()
                    return
                }
                start(activePlayer)
            }
        } else {
            activePlayer = player
            if pendingActivation == nil { start(player) }
        }
    }

    private func start(_ player: AVAudioPlayer) {
        let request = UUID()
        playbackRequest = request
        PlaybackAudioSession.performPlayerOperation {
            player.currentTime = 0
            return player.play() ? player.duration : nil
        } completion: { [weak self] (duration: TimeInterval?) in
            guard let self, playbackRequest == request else { return }
            guard let duration else {
                stop()
                return
            }
            finishTask = Task {
                do {
                    try await Task.sleep(for: .seconds(duration + 0.05))
                    self.stop()
                } catch {
                    // A new cue or pronunciation took over.
                }
            }
        }
    }

    func stop() {
        finishTask?.cancel()
        finishTask = nil
        pendingActivation = nil
        playbackRequest = nil
        guard let player = activePlayer else { return }
        activePlayer = nil
        PlaybackAudioSession.performPlayerOperation { player.stop() }
        PlaybackAudioSession.deactivate()
    }

    private func player(for cue: TapCue) -> AVAudioPlayer? {
        if let player = players[cue] { return player }
        guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Cues"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        players[cue] = player
        return player
    }
}
