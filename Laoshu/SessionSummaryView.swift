import SwiftUI
import LaoshuKit

/// Ends a session with how many were right the first time out of the words
/// introduced, and which words did not stick — by pinyin and meaning, no
/// dates and no schedule (D27).
struct SessionSummaryView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Session complete")
                .font(.title2.weight(.semibold))

            Text("\(session.firstAttemptRightCount) of \(session.drawnCount) right the first time")
                .font(.headline)

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
                            Text(word.definition)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LaoshuTheme.background)
    }
}
