import SwiftUI
import LaoshuKit

/// The placement test's card: pinyin large with the hanzi small and grey
/// beneath it, as the study card front does (D17). No speaker glyph and no
/// back — there is nothing to replay and nothing to reveal, since a
/// placement card never asks to be flipped.
struct PlacementCardView: View {
    let word: Word
    var dragAmount: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(word.pinyin)
                .font(.system(size: 42, weight: .semibold))
            Text(word.hanzi)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: LaoshuTheme.cornerRadius, style: .continuous)
                .fill(LaoshuTheme.cardBackground)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LaoshuTheme.cornerRadius, style: .continuous)
                .fill(dragAmount >= 0 ? LaoshuTheme.accent : Color.gray)
                .opacity(min(abs(dragAmount), 1) * 0.16)
        )
        .padding(.horizontal, 24)
    }
}
