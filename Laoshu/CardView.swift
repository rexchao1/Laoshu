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
/// caller, not here.
struct CardView: View {
    let card: Card
    let voiceAvailable: Bool
    let onFlip: () -> Void
    let onReplay: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            faceView(card.isFlipped ? card.answerFace : card.promptFace)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LaoshuTheme.cardBackground)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
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
