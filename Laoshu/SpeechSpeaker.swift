import AVFoundation

/// Speaks the hanzi string aloud on flip and on replay (D7). If no Mandarin
/// voice is installed, `voiceAvailable` is false, the speaker glyph shows
/// struck through, and `speak` is a no-op — a failed or missing voice is
/// silent, never a dialog.
final class SpeechSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    let voiceAvailable: Bool

    init() {
        voiceAvailable = AVSpeechSynthesisVoice(language: "zh-CN") != nil
    }

    func speak(_ hanzi: String) {
        guard voiceAvailable else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: hanzi)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
    }

    /// Cuts off whatever is speaking, for a screen that is going away.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
