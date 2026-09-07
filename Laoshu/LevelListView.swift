import SwiftUI
import LaoshuKit

/// The six levels, each with its word count. Tapping one opens a session
/// card screen for that level.
struct LevelListView: View {
    let engine: SessionEngine

    @State private var summaries: [LevelSummary] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    DatabaseErrorView(message: loadError)
                } else {
                    List(summaries, id: \.level) { summary in
                        NavigationLink(value: summary.level) {
                            HStack {
                                Text("Level \(summary.level)")
                                Spacer()
                                Text("\(summary.wordCount) words")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(LaoshuTheme.background)
                    .navigationDestination(for: Int.self) { level in
                        SessionView(engine: engine, level: level)
                    }
                }
            }
            .navigationTitle("Laoshu")
        }
        .task {
            loadSummaries()
        }
    }

    private func loadSummaries() {
        do {
            summaries = try engine.levelSummaries()
        } catch {
            loadError = "\(error)"
        }
    }
}
