import SwiftUI
import LaoshuKit

/// The level test's end screen: the raw score and whether it cleared route
/// line 9's pass mark. Diagnostic only — nothing here schedules anything,
/// and there is no list of which words were missed, since a level test is
/// a single pass with no per-word memory kept afterward.
struct LevelTestResultView: View {
    let result: LevelTestResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            IconBadge(systemName: result.passed ? "checkmark.seal.fill" : "seal")

            Text(result.passed ? "Passed" : "Not this time")
                .font(.title2.weight(.semibold))

            Text("\(result.correctCount) of \(result.totalCount) right, \(result.percentCorrect)%")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(LaoshuTheme.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LaoshuTheme.background)
    }
}
