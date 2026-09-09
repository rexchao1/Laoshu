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
    @State private var loadError: String?

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
}
