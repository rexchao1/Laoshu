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
    private let speaker = SpeechSpeaker()

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        ZStack {
            LaoshuTheme.background.ignoresSafeArea()

            if let loadError {
                DatabaseErrorView(message: loadError)
            } else if let session {
                if session.isFinished {
                    SessionSummaryView(session: session)
                } else if let card = session.currentCard {
                    sessionBody(session: session, card: card)
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
                    session.flipCurrentCard()
                    speaker.speak(card.word.hanzi)
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

    private func progress(for session: Session) -> Double {
        guard session.drawnCount > 0 else { return 1 }
        return Double(session.finishedCount + session.parkedCount) / Double(session.drawnCount)
    }

    /// Ignores the gesture entirely while the card is still showing its
    /// front (D26): no movement, no advance, no write.
    private func dragGesture(session: Session, card: Card) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard card.isFlipped else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard card.isFlipped else {
                    dragOffset = .zero
                    return
                }
                if value.translation.width > swipeThreshold {
                    dragOffset = .zero
                    try? session.swipe(.right)
                } else if value.translation.width < -swipeThreshold {
                    dragOffset = .zero
                    try? session.swipe(.left)
                } else {
                    dragOffset = .zero
                }
            }
    }
}
