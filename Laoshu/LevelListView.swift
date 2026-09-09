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
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(summary.wordCount) words")
                                        .foregroundStyle(.secondary)
                                    if summary.waitingCount > 0 {
                                        Text("\(summary.waitingCount) waiting")
                                            .font(.caption)
                                            .foregroundStyle(LaoshuTheme.accent)
                                    }
                                }
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
            // D26: `SessionEngine` isn't `@Observable`, so nothing tells
            // this view its counts are stale after a session or a day
            // rollover. This sits on the content inside the stack, not on
            // the stack itself: a `NavigationStack` never disappears when a
            // destination is pushed, so an `.onAppear` out there fires once
            // and is no better than the `.task` it replaced. In here it
            // fires again every time the list comes back to the top.
            .onAppear {
                loadSummaries()
            }
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
