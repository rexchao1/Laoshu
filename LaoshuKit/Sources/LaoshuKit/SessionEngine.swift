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
public struct Card: Sendable, Equatable {
    public let word: Word
    public private(set) var leftSwipeCount = 0
    public private(set) var isFlipped = false

    init(word: Word) {
        self.word = word
    }

    mutating func flip() {
        isFlipped = true
    }

    mutating func requeued() {
        leftSwipeCount += 1
        isFlipped = false
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

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        self.reviewLog = ReviewLog(dbQueue: dbQueue)
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

    /// Draws the eight lowest `word_index` words in `level` that have never
    /// been reviewed (D17, D18). Returns fewer than eight — reported by the
    /// session's `drawnCount` — if the level has fewer unseen words left.
    public func startSession(level: Int) throws -> Session {
        let words = try dbQueue.read { db in
            try Word.fetchAll(
                db,
                sql: """
                SELECT w.word_index, w.level, w.hanzi, w.pinyin, w.pinyin_numbered, w.definition
                FROM cat.word w
                LEFT JOIN review r ON r.word_index = w.word_index
                WHERE w.level = ? AND r.word_index IS NULL
                ORDER BY w.word_index ASC
                LIMIT 8;
                """,
                arguments: [level]
            )
        }
        return Session(words: words, reviewLog: reviewLog)
    }
}
