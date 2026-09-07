import SwiftUI

/// The slim bar across the top of a session, standing in for a text counter
/// (D28). `progress` is clamped to 0...1.
struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule().fill(LaoshuTheme.accent)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
    }
}
