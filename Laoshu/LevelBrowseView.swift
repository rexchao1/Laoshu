import SwiftUI
import LaoshuKit

/// The level's browse screen: every word already met, newest batch first, as
/// a read-only list. Nothing here flips, grades, or writes anything.
///
/// D6: a `List`, not a `ScrollView` over a `ForEach` — level 6 holds 1,800
/// words, and a `List` builds rows only as they scroll into view.
struct LevelBrowseView: View {
    let level: Int
    let engine: SessionEngine

    @State private var browseResult: BrowseResult?
    @State private var loadError: String?
    // D9: one speaker for the whole screen, held in `@State` so it survives
    // this view's body re-running. A plain stored property's initializer
    // would run again on every rebuild, and two synthesizers would mean a
    // stop on one leaving the other still talking.
    @State private var speaker = SpeechSpeaker()

    var body: some View {
        Group {
            if let loadError {
                DatabaseErrorView(message: loadError)
            } else if let browseResult {
                if browseResult.words.isEmpty {
                    emptyStateView
                } else {
                    List(browseResult.words, id: \.wordIndex) { word in
                        row(for: word)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(LaoshuTheme.background)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Level \(level)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadWords()
        }
        .onDisappear {
            speaker.stop()
        }
    }

    private var emptyStateView: some View {
        Text("Nothing has been studied in this level yet.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LaoshuTheme.background)
    }

    /// D14: the hanzi sits beneath the pinyin, small and grey, on the
    /// leading side — the same rule the card front follows. The meaning
    /// takes the remaining space and wraps as needed, and the speaker sits
    /// at the trailing edge.
    private func row(for word: Word) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.pinyin)
                    .font(.body.weight(.medium))
                Text(word.hanzi)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(word.definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button {
                speaker.speak(word.hanzi)
            } label: {
                Image(systemName: speaker.voiceAvailable ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(speaker.voiceAvailable ? LaoshuTheme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!speaker.voiceAvailable)
            .accessibilityLabel("Play pronunciation")
        }
        .padding(.vertical, 4)
    }

    private func loadWords() {
        guard browseResult == nil, loadError == nil else { return }
        do {
            browseResult = try engine.browse(level: level)
        } catch {
            loadError = "\(error)"
        }
    }
}
