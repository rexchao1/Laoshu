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
    @State private var voiceIdentifier: String?
    @State private var speechRate: Double = 0.5
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
                            .transition(.opacity)
                    } else if let card = test.currentCard {
                        testBody(test: test, card: card)
                            .transition(.opacity)
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
            loadAudioPreferences()
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
                dragAmount: dragOffset.width / swipeThreshold,
                onFlip: {
                    let isFirstReveal = !card.isFlipped && !card.hasBeenRevealed
                    withAnimation(.easeInOut(duration: 0.25)) {
                        test.flipCurrentCard()
                    }
                    if isFirstReveal && test.speakOnFlip {
                        speaker.speak(card.word.hanzi, voiceIdentifier: voiceIdentifier, rate: speechRate)
                    }
                },
                onReplay: {
                    speaker.speak(card.word.hanzi, voiceIdentifier: voiceIdentifier, rate: speechRate)
                }
            )
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
            .gesture(dragGesture(test: test))
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: dragOffset)
            .sensoryFeedback(.selection, trigger: card.isFlipped)
            .sensoryFeedback(.impact(weight: .light), trigger: card.word.hanzi)

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

    /// Same reasoning as `SessionView.loadAudioPreferences()`: read once,
    /// not carried by `LevelTest` itself.
    private func loadAudioPreferences() {
        do {
            let preferences = try engine.preferences()
            voiceIdentifier = preferences.voiceIdentifier
            speechRate = preferences.speechRate
        } catch {
            // Intentionally swallowed, same reasoning as `SessionView`.
        }
    }

    private func record(test: LevelTest, _ direction: SwipeDirection) {
        do {
            swipeError = nil
            try withAnimation(.easeInOut(duration: 0.25)) {
                try test.answer(direction)
            }
        } catch {
            swipeError = "That answer was not saved. \(error.localizedDescription)"
        }
    }

    /// A swipe grades the card whether or not it has been flipped, same as
    /// `SessionView`'s drag gesture.
    private func dragGesture(test: LevelTest) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
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
