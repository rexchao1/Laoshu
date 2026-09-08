import Foundation
import GRDB
import Observation

/// Which way a card was swiped.
public enum SwipeDirection: Sendable {
    case left
    case right
}

/// One word on screen during a session.
///
/// D20: a requeued card is a new presentation, so `isFlipped` resets to
/// `false` whenever the card goes back into the queue after a left swipe.
///
/// D26a: flipping is free in both directions, so `isFlipped` says only which
/// face is showing right now. What gates a swipe is `hasBeenRevealed`, which
/// turns true on the first flip to the back and stays true until a requeue.
/// The two differ as soon as the card is flipped back to re-read the pinyin.
public struct Card: Sendable, Equatable {
    public let word: Word
    public private(set) var leftSwipeCount = 0
    public private(set) var isFlipped = false

    /// Whether the meaning has been shown at least once in this presentation.
    public private(set) var hasBeenRevealed = false

    init(word: Word) {
        self.word = word
    }

    mutating func flip() {
        isFlipped.toggle()
        if isFlipped {
            hasBeenRevealed = true
        }
    }

    mutating func requeued() {
        leftSwipeCount += 1
        isFlipped = false
        hasBeenRevealed = false
    }
}

/// One study session: an in-memory queue of cards drawn from a single level,
/// and the rules for what a swipe does to that queue.
///
/// D22: session state lives only in memory. Closing the app abandons
/// whatever is left in the queue; the swipes already logged to `ReviewLog`
/// stand regardless.
@Observable
public final class Session {
    private let reviewLog: ReviewLog
    private var queue: [Card]

    /// How many words this session actually drew — eight, unless the level
    /// had fewer unseen words left (D20).
    public let drawnCount: Int
    public private(set) var finishedCount = 0
    public private(set) var parkedCount = 0

    /// How many of `drawnCount` were swiped right the first time they were
    /// shown, never having gone left first (D27).
    public private(set) var firstAttemptRightCount = 0

    /// Words parked by a third left swipe, in the order they parked (D27).
    public private(set) var parkedWords: [Word] = []

    init(words: [Word], reviewLog: ReviewLog) {
        self.reviewLog = reviewLog
        self.queue = words.map(Card.init)
        self.drawnCount = words.count
    }

    /// D20: the session ends once every drawn word has been swiped right
    /// once or swiped left three times.
    public var isFinished: Bool { queue.isEmpty }

    public var currentCard: Card? { queue.first }

    /// Turns the current card over, in either direction (D26a).
    public func flipCurrentCard() {
        guard !queue.isEmpty else { return }
        queue[0].flip()
    }

    /// Applies a swipe to the current card, logging it to `ReviewLog`
    /// regardless of outcome (D16). A right swipe finishes the word. A left
    /// swipe requeues it at least three cards later (D20's `min(3, ...)`
    /// placement below), or parks it without requeuing on the third left
    /// swipe.
    public func swipe(_ direction: SwipeDirection) throws {
        guard !queue.isEmpty else { return }
        var card = queue.removeFirst()

        switch direction {
        case .right:
            try reviewLog.record(wordIndex: card.word.wordIndex, grade: .good)
            finishedCount += 1
            if card.leftSwipeCount == 0 {
                firstAttemptRightCount += 1
            }

        case .left:
            try reviewLog.record(wordIndex: card.word.wordIndex, grade: .again)
            card.requeued()
            if card.leftSwipeCount >= 3 {
                parkedCount += 1
                parkedWords.append(card.word)
            } else {
                let insertIndex = min(3, queue.count)
                queue.insert(card, at: insertIndex)
            }
        }
    }
}

/// A level as it appears on the level list: its number and how many words
/// the catalogue holds for it, regardless of review state (D3).
public struct LevelSummary: Sendable, Equatable {
    public let level: Int
    public let wordCount: Int
}

/// Decides which words come next and hands out sessions.
public final class SessionEngine {
    private let dbQueue: DatabaseQueue
    public let reviewLog: ReviewLog

    /// Where the shuffle in `startSession` gets its randomness (D17a). The
    /// app leaves this at the system generator; tests pass a seeded one so a
    /// draw is reproducible.
    private var rng: any RandomNumberGenerator

    public init(dbQueue: DatabaseQueue, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.dbQueue = dbQueue
        self.reviewLog = ReviewLog(dbQueue: dbQueue)
        self.rng = rng
    }

    /// The six levels in the catalogue, in level order, each with its total
    /// word count. Counts the whole level, not what is left unseen.
    public func levelSummaries() throws -> [LevelSummary] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT level, COUNT(*) AS word_count FROM cat.word GROUP BY level ORDER BY level ASC;"
            ).map { row in
                LevelSummary(level: row["level"], wordCount: row["word_count"])
            }
        }
    }

    /// Draws eight words at random from those in `level` that have never been
    /// reviewed (D17a, D18). Returns fewer than eight — reported by the
    /// session's `drawnCount` — if the level has fewer unseen words left.
    ///
    /// The unseen pool is read as bare `word_index` values, shuffled here,
    /// and only the chosen eight are fetched as rows. Shuffling in Swift
    /// rather than with SQLite's `RANDOM()` is what makes the draw
    /// reproducible under a seeded generator; the pool is at most 1,800
    /// integers, so reading all of it costs nothing.
    public func startSession(level: Int) throws -> Session {
        let pool = try dbQueue.read { db in
            try Int.fetchAll(
                db,
                sql: """
                SELECT w.word_index
                FROM cat.word w
                LEFT JOIN review r ON r.word_index = w.word_index
                WHERE w.level = ? AND r.word_index IS NULL;
                """,
                arguments: [level]
            )
        }

        let chosen = Array(pool.shuffled(using: &rng).prefix(8))
        guard !chosen.isEmpty else {
            return Session(words: [], reviewLog: reviewLog)
        }

        let placeholders = databaseQuestionMarks(count: chosen.count)
        let rows = try dbQueue.read { db in
            try Word.fetchAll(
                db,
                sql: """
                SELECT word_index, level, hanzi, pinyin, pinyin_numbered, definition
                FROM cat.word
                WHERE word_index IN (\(placeholders));
                """,
                arguments: StatementArguments(chosen)
            )
        }

        // `IN` returns rows in whatever order SQLite likes, which would undo
        // the shuffle. Put them back into the drawn order.
        let byIndex = Dictionary(uniqueKeysWithValues: rows.map { ($0.wordIndex, $0) })
        let words = chosen.compactMap { byIndex[$0] }
        return Session(words: words, reviewLog: reviewLog)
    }
}
