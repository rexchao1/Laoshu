import SwiftUI
import LaoshuKit

/// The three zero-card screens (D13), each distinct from the normal summary:
/// today's allowance is spent but unseen words remain, nothing is unseen but
/// a batch is still on the ladder, or the level has nothing left to teach or
/// bring back at all. Which one shows is decided by `session.emptyReason`.
struct SessionEmptyStateView: View {
    let session: Session
    /// The most recent level test attempt on this level, if any — route
    /// line 9, shown only alongside the `.levelComplete` reason, the one
    /// state a level test can be taken from.
    let levelTestResult: LevelTestResult?
    let onDrawMore: () -> Void
    let onTakeLevelTest: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            IconBadge(systemName: iconName)

            Text(headline)
                .font(.title3.weight(.semibold))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if session.hasUnseenWordsRemaining {
                Button("Draw \(session.newWordsPerDay) more", action: onDrawMore)
                    .buttonStyle(.borderedProminent)
                    .tint(LaoshuTheme.accent)
            }

            if session.emptyReason == .levelComplete {
                if let levelTestResult {
                    Text("Last level test: \(levelTestResult.percentCorrect)%\(levelTestResult.passed ? ", passed" : "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Take the level test", action: onTakeLevelTest)
                    .buttonStyle(.bordered)
                    .tint(LaoshuTheme.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LaoshuTheme.background)
    }

    private var iconName: String {
        switch session.emptyReason {
        case .allowanceSpent: "hourglass"
        case .waitingOnLadder: "clock"
        case .levelComplete, nil: "checkmark.seal"
        }
    }

    private var headline: String {
        switch session.emptyReason {
        case .allowanceSpent: "Today's allowance is spent"
        case .waitingOnLadder: "Nothing due yet"
        case .levelComplete, nil: "Level finished"
        }
    }

    private var detail: String {
        switch session.emptyReason {
        case .allowanceSpent:
            "Another level already used today's new words. This level still has unseen words waiting."
        case .waitingOnLadder:
            if let returnOn = session.nextBatchReturnOn {
                "Every word here has been introduced. The next batch comes back \(returnOn.friendlyReturnPhrase)."
            } else {
                "Every word here has been introduced. Nothing is due yet."
            }
        case .levelComplete, nil:
            "Every word has been introduced and every batch has retired. There's nothing left to teach or bring back."
        }
    }
}
