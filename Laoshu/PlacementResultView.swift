import SwiftUI
import LaoshuKit

/// The placement test's end screen: the level it recommends and, by pinyin
/// and meaning, every word the walk marked as known (D17). Follows the voice
/// `SessionSummaryView` already uses for its own empty case (D17a).
struct PlacementResultView: View {
    let recommendedLevel: Int
    let knownWords: [Word]
    let onDone: () -> Void

    var body: some View {
        // A walk that ends at the ceiling marks up to twenty-five words, and a
        // definition can wrap, so the list is taller than a phone. Without the
        // scroll view the stack squeezed it and slid "Start studying" off the
        // bottom edge, and `safeAreaPadding` is here because the parent's
        // background ignores the safe area, which expands the stack around it
        // and drops this screen's first line under the status bar.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Placement complete")
                        .font(.title2.weight(.semibold))

                    Text("Level \(recommendedLevel) looks right for you.")
                        .font(.headline)

                    if knownWords.isEmpty {
                        Text("Nothing marked as known this time.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Marked as known")
                                .font(.subheadline.weight(.semibold))
                            ForEach(knownWords, id: \.wordIndex) { word in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(word.pinyin)
                                        .fontWeight(.medium)
                                    Text(word.definition)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            Button("Start studying", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(LaoshuTheme.accent)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LaoshuTheme.background)
    }
}
