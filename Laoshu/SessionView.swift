import SwiftUI
import LaoshuKit

/// Runs one study session for a level: the card stack, the swipe gesture,
/// and the summary once the queue is empty.
struct SessionView: View {
    let engine: SessionEngine
    let level: Int

    @State private var session: Session?
    @State private var loadError: String?
    @State private var dragOffset: CGSize = .zero
    @State private var swipeError: String?
    private let speaker = SpeechSpeaker()

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        ZStack {
            LaoshuTheme.background.ignoresSafeArea()

            if let loadError {
                DatabaseErrorView(message: loadError)
            } else if let session {
                if let card = session.currentCard {
                    sessionBody(session: session, card: card)
                } else if session.emptyReason != nil {
                    SessionEmptyStateView(session: session, onDrawEightMore: drawEightMore)
                } else {
                    SessionSummaryView(session: session, onDrawEightMore: drawEightMore)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Level \(level)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            startSession()
        }
    }

    private func sessionBody(session: Session, card: Card) -> some View {
        VStack(spacing: 20) {
            ProgressBar(progress: progress(for: session))
                .frame(height: 6)
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            CardView(
                card: card,
                voiceAvailable: speaker.voiceAvailable,
                onFlip: {
                    // Auto-play belongs to the reveal, not to every turn of
                    // the card (D7a). `card` is this presentation's state
                    // before the flip, so both flags being false means this
                    // tap is the first look at the meaning.
                    let isFirstReveal = !card.isFlipped && !card.hasBeenRevealed
                    session.flipCurrentCard()
                    if isFirstReveal {
                        speaker.speak(card.word.hanzi)
                    }
                },
                onReplay: {
                    speaker.speak(card.word.hanzi)
                }
            )
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
            .gesture(dragGesture(session: session, card: card))
            .animation(.interactiveSpring(), value: dragOffset)

            VStack(spacing: 6) {
                if let swipeError {
                    Text(swipeError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Text("tap to flip")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    HStack {
                        Text("forgot")
                        Spacer()
                        Text("knew")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 48)
                }
            }

            Spacer()
        }
    }

    private func startSession() {
        guard session == nil, loadError == nil else { return }
        do {
            session = try engine.startSession(level: level)
        } catch {
            loadError = "\(error)"
        }
    }

    /// The "eight more" button's action, on both the summary and the
    /// allowance-spent empty state: replaces the finished session with a
    /// fresh one drawing another eight new words, ignoring the day's
    /// allowance.
    private func drawEightMore() {
        do {
            session = try engine.startBonusSession(level: level)
        } catch {
            loadError = "\(error)"
        }
    }

    private func progress(for session: Session) -> Double {
        guard session.drawnCount > 0 else { return 1 }
        return Double(session.finishedCount + session.parkedCount) / Double(session.drawnCount)
    }

    /// Writes the swipe to the review log and surfaces a failure on the card.
    ///
    /// A swipe that could not be recorded is never treated as recorded: the
    /// session only advances when `swipe` returns, so a throw leaves the same
    /// card in place. The message matters because the review log is the only
    /// durable output of a session and the scheduler in a later checkpoint
    /// replays it; a swipe that vanished silently would leave that schedule
    /// wrong with nothing to show for it.
    private func record(session: Session, _ direction: SwipeDirection) {
        do {
            swipeError = nil
            try session.swipe(direction)
        } catch {
            swipeError = "That swipe was not saved. \(error.localizedDescription)"
        }
    }

    /// Ignores the gesture entirely until the meaning has been shown once
    /// (D26, D26a): no movement, no advance, no write. The gate is
    /// `hasBeenRevealed` rather than `isFlipped`, so flipping back to re-read
    /// the pinyin does not take away the ability to grade a word already
    /// seen, while a card whose answer was never shown still cannot be
    /// graded.
    private func dragGesture(session: Session, card: Card) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard card.hasBeenRevealed else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard card.hasBeenRevealed else {
                    dragOffset = .zero
                    return
                }
                if value.translation.width > swipeThreshold {
                    dragOffset = .zero
                    record(session: session, .right)
                } else if value.translation.width < -swipeThreshold {
                    dragOffset = .zero
                    record(session: session, .left)
                } else {
                    dragOffset = .zero
                }
            }
    }
}
