import SwiftUI
import LaoshuKit

/// Pushed from the level list's leading toolbar item: the streak, today's
/// waiting total, and each level's counts (D22). A pure read of the two kit
/// readers — nothing here writes anything.
struct ProgressScreen: View {
    let streakReader: StreakReader
    let progressStore: ProgressStore

    @State private var streak: Streak?
    @State private var progress: [LevelProgress]?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                DatabaseErrorView(message: loadError)
            } else {
                List {
                    Section {
                        streakRow
                        waitingRow
                    }
                    Section {
                        ForEach(progress ?? [], id: \.level) { level in
                            levelRow(for: level)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
        }
    }

    /// D21: the streak is one row in the same type size as the counts below
    /// it, not the largest thing on the screen.
    private var streakRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(streakHeadline)
            if let subtitle = streakSubtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var waitingRow: some View {
        Text(waitingHeadline)
    }

    private func levelRow(for level: LevelProgress) -> some View {
        HStack {
            Text("Level \(level.level)")
            Spacer()
            Text("\(level.learnedCount) learned, \(level.inProgressCount) in progress, \(level.leftCount) left")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Level \(level.level), \(level.learnedCount) learned, \(level.inProgressCount) in progress, \(level.leftCount) left"
        )
    }

    /// D22a, copied exactly.
    private var streakHeadline: String {
        switch streak?.days ?? 0 {
        case 0: return "No days yet"
        case 1: return "1 day studied"
        case let n: return "\(n) days studied"
        }
    }

    /// D22a, copied exactly: nothing underneath a zero streak.
    private var streakSubtitle: String? {
        guard let streak, streak.days > 0 else { return nil }
        switch streak.state {
        case .studiedToday: return "Studied today"
        case .notYetToday: return "Not yet today"
        case .restDayUsed: return "Rest day used, study today to keep it"
        case .none: return nil
        }
    }

    /// D22a, copied exactly.
    private var waitingHeadline: String {
        let total = (progress ?? []).reduce(0) { $0 + $1.waitingCount }
        switch total {
        case 0: return "Nothing waiting today"
        case 1: return "1 word waiting today"
        default: return "\(total) words waiting today"
        }
    }

    private func load() {
        do {
            streak = try streakReader.read()
            progress = try progressStore.progress()
        } catch {
            loadError = "\(error)"
        }
    }
}
