import SwiftUI
import LaoshuKit

/// The two places the level list can push to: a level's study session, or
/// its browse screen (D13).
enum LevelDestination: Hashable {
    case study(Int)
    case browse(Int)
    case progress
    case settings
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
    @State private var streak: Streak?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let loadError {
                    DatabaseErrorView(message: loadError)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(summaries, id: \.level) { summary in
                                HStack {
                                    Button {
                                        path.append(.study(summary.level))
                                    } label: {
                                        HStack {
                                            Text("Level \(summary.level)")
                                                .font(.body.weight(.semibold))
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
                                    .buttonStyle(PressableRowStyle())

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
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: LaoshuTheme.cornerRadius, style: .continuous)
                                        .fill(LaoshuTheme.cardBackground)
                                        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(LaoshuTheme.background)
                    .navigationDestination(for: LevelDestination.self) { destination in
                        switch destination {
                        case .study(let level):
                            SessionView(engine: engine, level: level)
                        case .browse(let level):
                            LevelBrowseView(level: level, engine: engine)
                        case .progress:
                            ProgressScreen(streakReader: streakReader, progressStore: progressStore)
                        case .settings:
                            SettingsScreen(preferenceStore: preferenceStore)
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
                                // An explicit stack rather than a `Label`: a
                                // toolbar button on iOS 26 draws a `Label` as
                                // its icon alone, even under
                                // `.labelStyle(.titleAndIcon)`, which hid the
                                // number this checkpoint exists to show.
                                HStack(spacing: 4) {
                                    Image(systemName: "flame")
                                    Text("\(streak.days)")
                                }
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
                        // `graduationcap` rather than `checklist`: the level
                        // row's own Browse button already uses a list glyph
                        // (`list.bullet`), and a second list-shaped icon here
                        // read as the same feature.
                        Image(systemName: "graduationcap")
                    }
                    .accessibilityLabel("Take placement test")
                }
                // Without the spacer iOS 26 packs both trailing items into
                // one glass capsule with no divider, so the checklist glyph
                // and this word read as a single segmented control.
                ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
                if loadError == nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            path.append(.settings)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
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
}

/// A level row dims and shrinks slightly while pressed, so tapping it feels
/// like pressing something rather than just triggering navigation.
private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
