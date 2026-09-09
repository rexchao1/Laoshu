import SwiftUI
import LaoshuKit

/// Runs the placement test presented over the level list: the card stack,
/// the swipe gesture, and the end screen once the walk stops.
///
/// D17: checkpoint 1's D26/D26a gate a study card's swipe on the card having
/// been revealed, so a card whose meaning was never shown cannot write a
/// review row. A placement card has no back and writes no review row, so
/// that gate has nothing to protect and would only make the card
/// unswipeable — this view owns its own gesture rather than reusing
/// `SessionView`'s.
struct PlacementTestView: View {
    let engine: SessionEngine
    let onFinished: (Int) -> Void
    let onSkip: () -> Void

    @State private var session: PlacementSession?
    @State private var loadError: String?
    @State private var dragOffset: CGSize = .zero
    @State private var swipeError: String?

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        NavigationStack {
            ZStack {
                LaoshuTheme.background.ignoresSafeArea()

                if let loadError {
                    DatabaseErrorView(message: loadError)
                } else if let session {
                    if let recommendedLevel = session.recommendedLevel {
                        PlacementResultView(
                            recommendedLevel: recommendedLevel,
                            knownWords: session.knownWords,
                            onDone: { onFinished(recommendedLevel) }
                        )
                    } else if let word = session.currentWord {
                        testBody(session: session, word: word)
                    } else {
                        ProgressView()
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Placement test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session?.recommendedLevel == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip", action: onSkip)
                    }
                }
            }
        }
        .task {
            start()
        }
    }

    private func testBody(session: PlacementSession, word: Word) -> some View {
        VStack(spacing: 20) {
            ProgressBar(progress: Double(session.wordsAnswered) / Double(PlacementTest.wordCeiling))
                .frame(height: 6)
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            PlacementCardView(word: word)
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                .gesture(dragGesture(session: session))
                .animation(.interactiveSpring(), value: dragOffset)

            VStack(spacing: 6) {
                if let swipeError {
                    Text(swipeError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    HStack {
                        Text("don't know")
                        Spacer()
                        Text("know it")
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
        guard session == nil, loadError == nil else { return }
        do {
            session = try engine.startPlacementTest()
        } catch {
            loadError = "\(error)"
        }
    }

    private func record(session: PlacementSession, _ answer: PlacementAnswer) {
        do {
            swipeError = nil
            try session.answer(answer)
        } catch {
            swipeError = "That answer was not saved. \(error.localizedDescription)"
        }
    }

    /// Not gated on a reveal (D17): there is nothing to reveal, so a swipe in
    /// either direction is live from the first frame.
    private func dragGesture(session: PlacementSession) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if value.translation.width > swipeThreshold {
                    dragOffset = .zero
                    record(session: session, .know)
                } else if value.translation.width < -swipeThreshold {
                    dragOffset = .zero
                    record(session: session, .dontKnow)
                } else {
                    dragOffset = .zero
                }
            }
    }
}
