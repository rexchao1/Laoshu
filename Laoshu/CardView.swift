import SwiftUI
import LaoshuKit

/// The card itself: whichever face `card.promptFace` and `card.answerFace`
/// say to show (D7, D8). The Chinese face is pinyin large with the hanzi
/// small and grey beneath it and the replay speaker under both (D4, D6,
/// D7a); the meaning face is the English definition alone (D5). The view
/// never branches on the session's direction, only on the face kind.
///
/// Tapping anywhere on the card turns it over, in either direction (D26a).
/// The speaker button is a child of that tap area and takes its own taps
/// first, so replaying audio never flips the card. Swiping is handled by the
/// caller, not here; `dragAmount` is the caller's live drag distance,
/// normalized to -1...1 by its own swipe threshold, purely so this view can
/// wash the card with a little live color as it goes — it never affects
/// what a swipe does.
struct CardView: View {
    let card: Card
    let voiceAvailable: Bool
    var dragAmount: CGFloat = 0
    let onFlip: () -> Void
    let onReplay: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            faceView(card.isFlipped ? card.answerFace : card.promptFace)
                .id(card.isFlipped)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onFlip)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func faceView(_ face: CardFace) -> some View {
        switch face {
        case .chinese:
            VStack(spacing: 6) {
                Text(card.word.pinyin)
                    .font(.system(size: 42, weight: .semibold))
                Text(card.word.hanzi)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button(action: onReplay) {
                Image(systemName: voiceAvailable ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title2)
                    .foregroundStyle(voiceAvailable ? LaoshuTheme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!voiceAvailable)
            .accessibilityLabel("Play pronunciation")
        case .meaning:
            Text(card.word.gloss)
                .font(.system(size: 26, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
