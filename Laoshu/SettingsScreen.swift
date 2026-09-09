import SwiftUI
import LaoshuKit

/// Pushed from the level list's gear: the three things the user can change
/// about how a session runs (D1). Every control writes on change; there is
/// no save button (D8).
struct SettingsScreen: View {
    let preferenceStore: PreferenceStore

    @State private var newWordsPerDay: Int = 8
    @State private var direction: StudyDirection = .receptive
    @State private var speakOnFlip: Bool = true
    @State private var voiceIdentifier: String?
    @State private var speechRate: Double = 0.5
    @State private var loadError: String?

    /// Read once, not through `PreferenceStore`: this is AVFoundation's own
    /// list of what the device has installed, which the kit cannot see.
    private let availableVoices = SpeechSpeaker.mandarinVoices()

    var body: some View {
        Group {
            if let loadError {
                DatabaseErrorView(message: loadError)
            } else {
                List {
                    Section("Study") {
                        Stepper(value: $newWordsPerDay, in: 4...20, step: 1) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("New words a day")
                                    Spacer()
                                    Text("\(newWordsPerDay)")
                                        .foregroundStyle(.secondary)
                                }
                                Text("about \(newWordsPerDay * 3) cards a day once the ladder fills")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: newWordsPerDay) {
                            writeNewWordsPerDay()
                        }

                        Picker("Ask with", selection: $direction) {
                            Text("Pinyin first").tag(StudyDirection.receptive)
                            Text("English first").tag(StudyDirection.reverse)
                        }
                        .onChange(of: direction) {
                            writeDirection()
                        }
                    }

                    Section("Audio") {
                        Toggle("Say the word when a card turns over", isOn: $speakOnFlip)
                            .onChange(of: speakOnFlip) {
                                writeSpeakOnFlip()
                            }

                        if availableVoices.isEmpty {
                            Text("No Mandarin voice is installed on this device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            if availableVoices.count > 1 {
                                Picker("Voice", selection: $voiceIdentifier) {
                                    Text("Default").tag(nil as String?)
                                    ForEach(availableVoices) { voice in
                                        Text(voice.name).tag(voice.id as String?)
                                    }
                                }
                                .onChange(of: voiceIdentifier) {
                                    writeVoiceIdentifier()
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Speed")
                                HStack {
                                    Text("slower")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Slider(value: $speechRate, in: 0...1)
                                    Text("faster")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onChange(of: speechRate) {
                                writeSpeechRate()
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(LaoshuTheme.background)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
        }
    }

    private func load() {
        do {
            let preferences = try preferenceStore.preferences()
            newWordsPerDay = preferences.newWordsPerDay
            direction = preferences.direction
            speakOnFlip = preferences.speakOnFlip
            voiceIdentifier = preferences.voiceIdentifier
            speechRate = preferences.speechRate
        } catch {
            loadError = "\(error)"
        }
    }

    /// D8: a failed write leaves the control reading the value still in the
    /// database, and does not set `loadError`.
    private func writeNewWordsPerDay() {
        do {
            try preferenceStore.setNewWordsPerDay(newWordsPerDay)
            newWordsPerDay = try preferenceStore.preferences().newWordsPerDay
        } catch {
            // Intentionally swallowed, per D8.
        }
    }

    private func writeDirection() {
        do {
            try preferenceStore.setDirection(direction)
            direction = try preferenceStore.direction()
        } catch {
            // Intentionally swallowed, per D8.
        }
    }

    private func writeSpeakOnFlip() {
        do {
            try preferenceStore.setSpeakOnFlip(speakOnFlip)
            speakOnFlip = try preferenceStore.preferences().speakOnFlip
        } catch {
            // Intentionally swallowed, per D8.
        }
    }

    private func writeVoiceIdentifier() {
        do {
            try preferenceStore.setVoiceIdentifier(voiceIdentifier)
            voiceIdentifier = try preferenceStore.preferences().voiceIdentifier
        } catch {
            // Intentionally swallowed, per D8.
        }
    }

    private func writeSpeechRate() {
        do {
            try preferenceStore.setSpeechRate(speechRate)
            speechRate = try preferenceStore.preferences().speechRate
        } catch {
            // Intentionally swallowed, per D8.
        }
    }
}
