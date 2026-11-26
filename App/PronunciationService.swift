import AVFoundation
import UIKit
import Observation

enum EnglishAccent: String, CaseIterable {
    case american = "en-US"
    case british = "en-GB"

    var abbreviation: String {
        switch self {
        case .american: "US"
        case .british: "UK"
        }
    }

    var title: String {
        switch self {
        case .american: "انگلیسی آمریکایی"
        case .british: "انگلیسی بریتانیایی"
        }
    }

    static func preferred(_ storedValue: String) -> Self {
        Self(rawValue: storedValue) ?? .american
    }

    func bestVoice<Voice>(in voices: [Voice], language: (Voice) -> String,
                          quality: (Voice) -> Int) -> Voice? {
        voices
            .filter { language($0).caseInsensitiveCompare(rawValue) == .orderedSame }
            .max { quality($0) < quality($1) }
    }
}

@MainActor @Observable final class PronunciationService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = PronunciationService()

    enum PlaybackError: Error {
        case voiceUnavailable(EnglishAccent)
        case audioUnavailable

        var message: String {
            switch self {
            case .voiceUnavailable(let accent):
                "صدای \(accent.title) روی این دستگاه در دسترس نیست. می‌توانی آن را از بخش دسترس‌پذیری در تنظیمات آیفون اضافه کنی."
            case .audioUnavailable:
                "پخش صدا ممکن نشد. پس از پایان تماس یا وقفهٔ صوتی، دوباره امتحان کن."
            }
        }
    }

    enum PlaybackState { case ready, playing, paused, finished }

    private var playbackOwner: UUID?
    private var finishedOwner: UUID?
    private var paused = false

    func playbackState(for owner: UUID) -> PlaybackState {
        if playbackOwner == owner { return paused ? .paused : .playing }
        return finishedOwner == owner ? .finished : .ready
    }

    func pause(for owner: UUID) {
        guard playbackOwner == owner, !paused else { return }
        if synthesizer.pauseSpeaking(at: .immediate) { paused = true }
    }

    func resume(for owner: UUID) {
        guard playbackOwner == owner, paused else { return }
        if synthesizer.continueSpeaking() { paused = false }
    }

    func stop(for owner: UUID) {
        if finishedOwner == owner { finishedOwner = nil }
        guard playbackOwner == owner else { return }
        cancelUtterance()
        releaseSession()
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var currentUtterance: AVSpeechUtterance?
    private var ownsActiveSession = false

    var isPlaying: Bool { currentUtterance != nil }

    private override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true

        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(audioInterrupted(_:)),
                                  name: AVAudioSession.interruptionNotification, object: audioSession)
        notifications.addObserver(self, selector: #selector(didEnterBackground(_:)),
                                  name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func speak(_ text: String, accent: EnglishAccent, slowly: Bool, owner: UUID? = nil) throws(PlaybackError) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let installedVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        guard let voice = accent.bestVoice(in: installedVoices, language: { $0.language },
                                            quality: { $0.quality.rawValue }) else {
            throw .voiceUnavailable(accent)
        }

        TapSoundPlayer.shared.stop()
        cancelUtterance()
        if !ownsActiveSession {
            do {
                try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
                try audioSession.setActive(true)
                ownsActiveSession = true
            } catch {
                throw .audioUnavailable
            }
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = slowly
            ? max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 0.72)
            : AVSpeechUtteranceDefaultSpeechRate
        playbackOwner = owner
        finishedOwner = nil
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    private func cancelUtterance() {
        guard currentUtterance != nil else { return }
        currentUtterance = nil
        playbackOwner = nil
        paused = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func releaseSession() {
        guard ownsActiveSession else { return }
        ownsActiveSession = false
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              type == AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor [weak self] in
            // iOS has already deactivated the session. A new tap can try to activate it again.
            self?.ownsActiveSession = false
            self?.cancelUtterance()
        }
    }

    @objc nonisolated private func didEnterBackground(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.cancelUtterance()
            self?.releaseSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        endPlayback(for: ObjectIdentifier(utterance), finished: true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        endPlayback(for: ObjectIdentifier(utterance), finished: false)
    }

    nonisolated private func endPlayback(for id: ObjectIdentifier, finished: Bool) {
        Task { @MainActor [weak self] in
            // A callback from a replaced utterance must not deactivate the new one.
            guard let self, let current = currentUtterance, ObjectIdentifier(current) == id else { return }
            finishedOwner = finished ? playbackOwner : nil
            playbackOwner = nil
            paused = false
            currentUtterance = nil
            releaseSession()
        }
    }
}
