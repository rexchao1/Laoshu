import SwiftUI
import LaoshuKit

/// The card itself: pinyin large with the hanzi small and grey beneath it on
/// the front (D4, D6); the English meaning and a replay speaker on the back
/// (D5, D7). Tapping the front flips it; the front does not respond to taps
/// once flipped, and swiping is handled by the caller, not here.
struct CardView: View {
    let card: Card
    let voiceAvailable: Bool
    let onFlip: () -> Void
    let onReplay: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if card.isFlipped {
                Text(card.word.definition)
                    .font(.system(size: 26, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: onReplay) {
                    Image(systemName: voiceAvailable ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.title2)
                        .foregroundStyle(voiceAvailable ? LaoshuTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    Text(card.word.pinyin)
                        .font(.system(size: 42, weight: .semibold))
                    Text(card.word.hanzi)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onFlip)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        )
        .padding(.horizontal, 24)
    }
}
