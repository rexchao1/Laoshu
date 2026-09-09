import SwiftUI
import LaoshuKit

/// The six levels, each with its word count. Tapping one opens a session
/// card screen for that level.
struct LevelListView: View {
    let engine: SessionEngine

    @State private var summaries: [LevelSummary] = []
    @State private var loadError: String?
    @State private var path: [Int] = []
    @State private var showPlacementTest = false

    var body: some View {
        NavigationStack(path: $path) {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPlacementTest = true
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Take placement test")
                }
            }
            // D26: `SessionEngine` isn't `@Observable`, so nothing tells
            // this view its counts are stale after a session or a day
            // rollover. This sits on the content inside the stack, not on
            // the stack itself: a `NavigationStack` never disappears when a
            // destination is pushed, so an `.onAppear` out there fires once
            // and is no better than the `.task` it replaced. In here it
            // fires again every time the list comes back to the top.
            .onAppear {
                loadSummaries()
                checkPlacementGate()
            }
        }
        // D11: presented over the level list rather than replacing it — the
        // list, and the `NavigationStack` that owns `path`, stay mounted
        // underneath for the whole time this cover is up.
        .fullScreenCover(isPresented: $showPlacementTest) {
            PlacementTestView(
                engine: engine,
                onFinished: { recommendedLevel in
                    showPlacementTest = false
                    path.append(recommendedLevel)
                },
                onSkip: {
                    do {
                        try engine.declinePlacementTest()
                    } catch {
                        loadError = "\(error)"
                    }
                    showPlacementTest = false
                }
            )
        }
    }

    private func loadSummaries() {
        do {
            summaries = try engine.levelSummaries()
        } catch {
            loadError = "\(error)"
        }
    }

    /// Fires the first-launch gate only when placement genuinely has not
    /// been taken (D11a) — a test already taken or declined leaves this a
    /// no-op even though `onAppear` runs again every time the list comes
    /// back to the top.
    private func checkPlacementGate() {
        guard !showPlacementTest else { return }
        do {
            if case .notTaken = try engine.placementStatus() {
                showPlacementTest = true
            }
        } catch {
            loadError = "\(error)"
        }
    }
}
