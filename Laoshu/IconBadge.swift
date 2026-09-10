import SwiftUI

/// The icon atop an empty state, error, or end screen: a system image in a
/// soft circular badge instead of a bare glyph, so those screens read as
/// finished rather than placeholder.
struct IconBadge: View {
    let systemName: String
    var tint: Color = LaoshuTheme.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.largeTitle)
            .foregroundStyle(tint)
            .frame(width: 64, height: 64)
            .background(Circle().fill(tint.opacity(0.12)))
    }
}
