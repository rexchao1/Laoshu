import AVFoundation

/// One installed voice `SettingsScreen` can offer without importing
/// AVFoundation itself — plain data copied out of `AVSpeechSynthesisVoice`,
/// which is the only type in this file any other file needs to know about.
struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Speaks the hanzi string aloud on flip and on replay (D7), in whichever
/// installed Mandarin voice and speed route line 13 lets the user choose.
/// If no Mandarin voice is installed at all, `voiceAvailable` is false, the
/// speaker glyph shows struck through, and `speak` is a no-op — a failed or
/// missing voice is silent, never a dialog.
final class SpeechSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    let voiceAvailable: Bool

    init() {
        voiceAvailable = !Self.mandarinVoices().isEmpty
        // Without an explicit category, speech plays through
        // `.soloAmbient`'s default, which the silent switch mutes — a real
        // defect in a study app whose whole point is the audio. `.playback`
        // plays regardless of the switch; `.spokenAudio` is the mode Apple
        // documents for exactly this case; `.duckOthers` lowers background
        // audio instead of cutting it, since a card's one-word utterance is
        // short enough not to need the room to itself. A failed activation
        // is swallowed the same way a missing voice is: speech may then be
        // silenced by the switch or another app, which is the state before
        // this fix existed, not a new failure.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Every installed voice for Mandarin as shipped from mainland China —
    /// the HSK syllabus's own variety — in whatever order the system lists
    /// them. A device can hold more than one (the default compact voice
    /// alongside a downloaded enhanced or premium one); letting the user
    /// choose among them by name is this checkpoint's reading of the
    /// "voice-by-language defect" checkpoint 6 named but did not describe —
    /// `AVSpeechSynthesisVoice(language:)`, passed a bare language tag
    /// rather than a specific voice, silently returns whichever installed
    /// voice AVFoundation ranks first, with no way for the user to ask for
    /// a different one.
    static func mandarinVoices() -> [SpeechVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-CN" }
            .map { SpeechVoiceOption(id: $0.identifier, name: $0.name) }
    }

    /// Speaks `hanzi` in `voiceIdentifier` if it names a voice still
    /// installed, otherwise in the first of `mandarinVoices()` — read fresh
    /// on every call (`SessionView` and `LevelTestView` pass whatever
    /// `SessionEngine.preferences()` last returned) rather than cached at
    /// init, so a change in Settings takes effect on the very next card.
    func speak(_ hanzi: String, voiceIdentifier: String?, rate: Double) {
        guard voiceAvailable else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: hanzi)
        utterance.voice = resolvedVoice(preferring: voiceIdentifier)
        utterance.rate = Float(rate)
        synthesizer.speak(utterance)
    }

    private func resolvedVoice(preferring identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        if let firstInstalled = Self.mandarinVoices().first {
            return AVSpeechSynthesisVoice(identifier: firstInstalled.id)
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    /// Cuts off whatever is speaking, for a screen that is going away.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
