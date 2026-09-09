import Foundation
import GRDB

/// One level test in progress: a single pass over a sample of a level's
/// words, graded and never requeued (route line 9). Unlike `Session`, a left
/// swipe here is a final wrong answer, not a retry — this is a diagnostic
/// snapshot of what the user still recalls, not another study drill on the
/// same words.
///
/// Nothing is written until the last card is answered (mirroring
/// `PlacementSession`'s "abandoned leaves no trace"), and nothing this class
/// does ever creates, advances, or retires a batch: the user's chosen answer
/// to "what should a failed level test do" was "diagnostic only, no schedule
/// change" (review answer, 2026-09-09), so a level test can only ever record
/// its own score, never touch the ladder.
@Observable
public final class LevelTest {
    /// How many words one level test samples from the level, capped at
    /// however many the level actually has (only relevant to a tiny test
    /// fixture; every real level has far more than this).
    static let size = 20

    /// The share correct needed to mark the attempt passed. Diagnostic only
    /// (see above): passing sets no state anywhere but this attempt's own
    /// row, and failing does not requeue or unretire anything.
    static let passThreshold = 0.8

    private let dbQueue: DatabaseQueue
    private let today: TodayProvider
    private let level: Int
    private var queue: [Card]

    public let totalCount: Int
    public private(set) var answeredCount = 0
    public private(set) var correctCount = 0

    /// The `speak_on_flip` setting as it stood at the draw, read the same
    /// way `Session.speakOnFlip` is, so a card's first reveal speaks the
    /// word the same way it would in an ordinary study session.
    public let speakOnFlip: Bool

    /// Set once the last card is answered and the result is written.
    public private(set) var result: LevelTestResult?

    init(words: [Word], dbQueue: DatabaseQueue, today: TodayProvider, level: Int, direction: StudyDirection, speakOnFlip: Bool) {
        self.dbQueue = dbQueue
        self.today = today
        self.level = level
        self.queue = words.map { Card(word: $0, direction: direction) }
        self.totalCount = words.count
        self.speakOnFlip = speakOnFlip
    }

    public var currentCard: Card? { queue.first }
    public var isFinished: Bool { result != nil }

    /// Turns the current card over, exactly like a study session's card.
    public func flipCurrentCard() {
        guard !queue.isEmpty else { return }
        queue[0].flip()
    }

    /// Grades the current card and drops it from the queue for good — a
    /// left swipe here is a recorded wrong answer, not a requeue. Once the
    /// queue empties this writes the one `level_test` row for `level`,
    /// replacing whatever attempt was there before.
    public func answer(_ direction: SwipeDirection) throws {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        answeredCount += 1
        if direction == .right {
            correctCount += 1
        }

        guard queue.isEmpty else { return }
        let passed = totalCount > 0 && Double(correctCount) / Double(totalCount) >= Self.passThreshold
        let attempt = LevelTestResult(
            level: level,
            takenOn: today.today(),
            correctCount: correctCount,
            totalCount: totalCount,
            passed: passed
        )
        try LevelTestStore(dbQueue: dbQueue).record(attempt)
        result = attempt
    }
}
