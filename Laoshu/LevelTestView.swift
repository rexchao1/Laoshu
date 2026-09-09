import SwiftUI
import LaoshuKit

/// Runs a level test (route line 9): the same card and swipe gesture as a
/// study session, but every card is graded once and dropped — a left swipe
/// is a final wrong answer, not a requeue — and the end screen shows the
/// score rather than a "draw more" button.
struct LevelTestView: View {
    let engine: SessionEngine
    let level: Int
    let onDone: () -> Void

    @State private var test: LevelTest?
    @State private var loadError: String?
    @State private var dragOffset: CGSize = .zero
    @State private var swipeError: String?
    private let speaker = SpeechSpeaker()

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        NavigationStack {
            ZStack {
                LaoshuTheme.background.ignoresSafeArea()

                if let loadError {
                    DatabaseErrorView(message: loadError)
                } else if let test {
                    if let result = test.result {
                        LevelTestResultView(result: result, onDone: onDone)
                    } else if let card = test.currentCard {
                        testBody(test: test, card: card)
                    } else {
                        ProgressView()
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Level \(level) test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if test?.result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onDone)
                    }
                }
            }
        }
        .task {
            start()
        }
    }

    private func testBody(test: LevelTest, card: Card) -> some View {
        VStack(spacing: 20) {
            ProgressBar(progress: Double(test.answeredCount) / Double(test.totalCount))
                .frame(height: 6)
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            CardView(
                card: card,
                voiceAvailable: speaker.voiceAvailable,
                onFlip: {
                    let isFirstReveal = !card.isFlipped && !card.hasBeenRevealed
                    test.flipCurrentCard()
                    if isFirstReveal && test.speakOnFlip {
                        speaker.speak(card.word.hanzi)
                    }
                },
                onReplay: {
                    speaker.speak(card.word.hanzi)
                }
            )
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
            .gesture(dragGesture(test: test, card: card))
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
                        Text("wrong")
                        Spacer()
                        Text("right")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 48)
                }
            }

            Spacer()
        }
    }

    private func start() {
        guard test == nil, loadError == nil else { return }
        do {
            test = try engine.startLevelTest(level: level)
        } catch {
            loadError = "\(error)"
        }
    }

    private func record(test: LevelTest, _ direction: SwipeDirection) {
        do {
            swipeError = nil
            try test.answer(direction)
        } catch {
            swipeError = "That answer was not saved. \(error.localizedDescription)"
        }
    }

    /// Gated on a reveal exactly like a study session's card (D26, D26a in
    /// `SessionView`): no grading a card whose answer was never shown.
    private func dragGesture(test: LevelTest, card: Card) -> some Gesture {
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
                    record(test: test, .right)
                } else if value.translation.width < -swipeThreshold {
                    dragOffset = .zero
                    record(test: test, .left)
                } else {
                    dragOffset = .zero
                }
            }
    }
}
