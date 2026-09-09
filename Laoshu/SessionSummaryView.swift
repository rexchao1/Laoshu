import SwiftUI
import LaoshuKit

/// Ends a session with how many were right the first time out of every word
/// the session held, which words did not stick — by pinyin and meaning, no
/// dates and no schedule for those (D27) — and, when the session introduced
/// new words, the one line naming when those specific words come back
/// (D24). A due batch the session also held is never mentioned by date.
struct SessionSummaryView: View {
    let session: Session
    let onDrawEightMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Session complete")
                .font(.title2.weight(.semibold))

            Text("\(session.firstAttemptRightCount) of \(session.drawnCount) right the first time")
                .font(.headline)

            if let newWordsReturnOn = session.newWordsReturnOn {
                Text("The words you just learned come back \(newWordsReturnOn.friendlyReturnPhrase).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if session.parkedWords.isEmpty {
                Text("Nothing to park this time.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Didn't stick yet")
                        .font(.subheadline.weight(.semibold))
                    ForEach(session.parkedWords, id: \.wordIndex) { word in
                        HStack {
                            Text(word.pinyin)
                                .fontWeight(.medium)
                            Text(word.gloss)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if session.hasUnseenWordsRemaining {
                Button("Draw eight more", action: onDrawEightMore)
                    .buttonStyle(.borderedProminent)
                    .tint(LaoshuTheme.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LaoshuTheme.background)
    }
}
