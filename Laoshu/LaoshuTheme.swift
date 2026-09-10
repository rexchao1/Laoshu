import SwiftUI

/// The look decided in D28/D29: a cool near-white ground, a green accent for
/// progress and the affirmative side of a swipe. `background`,
/// `cardBackground`, and `progressTrack` are asset-catalog colors so each
/// carries a dark-mode counterpart (`Assets.xcassets`); `accent` is one
/// literal value that reads fine on both. Nothing else in the app picks its
/// own colors.
enum LaoshuTheme {
    static let background = Color("AppBackground")

    /// The raised surface a card sits on above `background`.
    static let cardBackground = Color("CardBackground")

    /// A progress bar's unfilled track, against `background`.
    static let progressTrack = Color("ProgressTrack")

    static let accent = Color(red: 0.20, green: 0.68, blue: 0.42)

    /// The one corner radius every card and raised row in the app shares.
    static let cornerRadius: CGFloat = 20
}
