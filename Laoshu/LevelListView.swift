import SwiftUI
import LaoshuKit

/// The two places the level list can push to: a level's study session, or
/// its browse screen (D13).
enum LevelDestination: Hashable {
    case study(Int)
    case browse(Int)
    case progress
}

/// The six levels, each with its word count. Tapping a row opens a session
/// card screen for that level; tapping its trailing Browse button opens that
/// level's browse screen instead.
struct LevelListView: View {
    let engine: SessionEngine
    let preferenceStore: PreferenceStore
    let streakReader: StreakReader
    let progressStore: ProgressStore

    @State private var summaries: [LevelSummary] = []
    @State private var loadError: String?
    @State private var path: [LevelDestination] = []
    @State private var showPlacementTest = false
    @State private var direction: StudyDirection = .receptive
    @State private var streak: Streak?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let loadError {
                    DatabaseErrorView(message: loadError)
                } else {
                    List(summaries, id: \.level) { summary in
                        HStack {
                            Button {
                                path.append(.study(summary.level))
                            } label: {
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                path.append(.browse(summary.level))
                            } label: {
                                // `list.bullet` because this opens a list of
                                // words, and the accent because every other
                                // coloured thing on this screen is that green
                                // (D28). A borderless button tints itself
                                // system blue otherwise, which is the only
                                // blue in the app.
                                Image(systemName: "list.bullet")
                                    .foregroundStyle(LaoshuTheme.accent)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Browse level \(summary.level)")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(LaoshuTheme.background)
                    .navigationDestination(for: LevelDestination.self) { destination in
                        switch destination {
                        case .study(let level):
                            SessionView(engine: engine, level: level)
                        case .browse(let level):
                            LevelBrowseView(level: level, engine: engine)
                        case .progress:
                            ProgressScreen(streakReader: streakReader, progressStore: progressStore)
                        }
                    }
                }
            }
            .navigationTitle("Laoshu")
            .toolbar {
                if loadError == nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            path.append(.progress)
                        } label: {
                            if let streak, streak.days > 0 {
                                Label("\(streak.days)", systemImage: "flame")
                            } else {
                                Image(systemName: "flame")
                            }
                        }
                        .accessibilityLabel(progressAccessibilityLabel)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPlacementTest = true
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Take placement test")
                }
                // Without the spacer iOS 26 packs both trailing items into
                // one glass capsule with no divider, so the checklist glyph
                // and this word read as a single segmented control.
                ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        toggleDirection()
                    } label: {
                        Text(directionLabel(direction))
                    }
                    .accessibilityLabel("Study direction: \(directionLabel(direction))")
                    .accessibilityHint("Switches to the other direction")
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
                loadDirection()
                loadStreak()
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
                    path.append(.study(recommendedLevel))
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

    /// D4: the label has to say which way the next session will ask, and
    /// "Receptive" and "Reverse" are words about the app rather than about
    /// the card. These read as the card does: what is on the front, then
    /// what the user has to come up with.
    private func directionLabel(_ direction: StudyDirection) -> String {
        switch direction {
        case .receptive: return "Pinyin first"
        case .reverse: return "English first"
        }
    }

    private func loadDirection() {
        do {
            direction = try preferenceStore.direction()
        } catch {
            loadError = "\(error)"
        }
    }

    /// A failed streak read leaves the bare flame rather than failing the
    /// whole level list — the streak is decoration on this screen, not its
    /// content.
    private func loadStreak() {
        do {
            streak = try streakReader.read()
        } catch {
            // Intentionally swallowed: the toolbar falls back to the bare flame.
        }
    }

    /// D19, copied exactly.
    private var progressAccessibilityLabel: String {
        switch streak?.days ?? 0 {
        case 0: return "Progress, no days yet"
        case 1: return "Progress, 1 day studied"
        case let n: return "Progress, \(n) days studied"
        }
    }

    /// D4a: a failed write leaves the label exactly where it was. The label
    /// is re-read from the store rather than flipped optimistically, so it
    /// never claims a direction that a failed write did not actually store.
    /// Unlike a failed placement decline, this does not set `loadError` —
    /// losing the whole level list over an unsaved preference is worse than
    /// the preference silently not saving.
    private func toggleDirection() {
        do {
            let next: StudyDirection = direction == .receptive ? .reverse : .receptive
            try preferenceStore.setDirection(next)
            direction = try preferenceStore.direction()
        } catch {
            // Intentionally swallowed, per D4a.
        }
    }
}
