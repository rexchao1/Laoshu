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
///
/// D3, D7: the words are drawn up front, but the batch they came from (if
/// any is due) only advances its ladder, and the batch of new words among
/// them only gets written, on the session's first swipe — never on a mere
/// draw. That first swipe writes both in the same transaction as its review
/// row, so a session entered and abandoned without a swipe leaves no trace
/// and spends no allowance.
@Observable
public final class Session {
    /// Why a session drew zero cards — the three states a caller needs to
    /// tell apart to show something other than an empty queue (D13).
    public enum EmptyReason: Sendable, Equatable {
        /// Unseen words remain, but another level already spent today's
        /// allowance of eight, and this level has no batch due today.
        case allowanceSpent
        /// Every word in the level has been introduced, and at least one
        /// batch is still on the ladder, waiting for a look that isn't due
        /// yet.
        case waitingOnLadder
        /// Every word in the level has been introduced and every batch has
        /// retired — there is nothing left to teach or bring back.
        case levelComplete
    }

    private let dbQueue: DatabaseQueue
    private let today: TodayProvider
    private let level: Int
    private let newWordIndices: [Int]
    private let dueBatchIDs: [Int64]
    private var hasWrittenFirstSwipe = false
    private var queue: [Card]

    /// How many words this session actually drew: every due batch's words
    /// plus up to eight new ones (D6), unless the level had fewer of either
    /// left (D20).
    public let drawnCount: Int
    public private(set) var finishedCount = 0
    public private(set) var parkedCount = 0

    /// Set only when `drawnCount == 0`, explaining which of the three empty
    /// states this is (D13).
    public let emptyReason: EmptyReason?

    /// How many of `drawnCount` were swiped right the first time they were
    /// shown, never having gone left first (D27).
    public private(set) var firstAttemptRightCount = 0

    /// Words parked by a third left swipe, in the order they parked (D27).
    public private(set) var parkedWords: [Word] = []

    /// When the words this session introduced come back for their first
    /// look, or `nil` when the session introduced none. Computed the same
    /// way the batch actually written on the first swipe will be scheduled,
    /// so it never drifts from what gets written (D24).
    public let newWordsReturnOn: LocalDate?

    /// Whether the level still has unseen words left after this session's
    /// own draw — what decides whether the "eight more" button appears.
    public let hasUnseenWordsRemaining: Bool

    /// When the level's next active batch comes back, set only for the
    /// `.waitingOnLadder` empty reason.
    public let nextBatchReturnOn: LocalDate?

    init(
        words: [Word],
        dbQueue: DatabaseQueue,
        today: TodayProvider,
        level: Int,
        newWordIndices: [Int],
        dueBatchIDs: [Int64],
        emptyReason: EmptyReason? = nil,
        hasUnseenWordsRemaining: Bool = false,
        nextBatchReturnOn: LocalDate? = nil
    ) {
        self.dbQueue = dbQueue
        self.today = today
        self.level = level
        self.newWordIndices = newWordIndices
        self.dueBatchIDs = dueBatchIDs
        self.queue = words.map(Card.init)
        self.drawnCount = words.count
        self.emptyReason = emptyReason
        self.newWordsReturnOn = newWordIndices.isEmpty
            ? nil
            : BatchScheduler.createBatch(level: level, today: today).nextLookOn
        self.hasUnseenWordsRemaining = hasUnseenWordsRemaining
        self.nextBatchReturnOn = nextBatchReturnOn
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
    ///
    /// The first swipe of a session also writes the batch of new words it
    /// drew (if any) and advances every due batch it drew from, all inside
    /// the same transaction as this swipe's review row (D7, D7a).
    public func swipe(_ direction: SwipeDirection) throws {
        guard !queue.isEmpty else { return }
        var card = queue.removeFirst()
        let grade: Grade = direction == .right ? .good : .again

        try dbQueue.write { db in
            try ReviewLog.record(db, wordIndex: card.word.wordIndex, grade: grade, at: Date())

            if !self.hasWrittenFirstSwipe {
                if !self.newWordIndices.isEmpty {
                    try BatchStore.createBatch(db, level: self.level, wordIndices: self.newWordIndices, today: self.today)
                }
                for batchID in self.dueBatchIDs {
                    try BatchStore.recordLook(db, batchID: batchID, today: self.today)
                }
            }
        }
        hasWrittenFirstSwipe = true

        switch direction {
        case .right:
            finishedCount += 1
            if card.leftSwipeCount == 0 {
                firstAttemptRightCount += 1
            }

        case .left:
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

/// A level as it appears on the level list: its number, how many words the
/// catalogue holds for it regardless of review state (D3), and how many of
/// those are waiting today — held by a batch of that level whose look is due
/// on or before today. `waitingCount` never counts the eight new words a
/// session would add.
public struct LevelSummary: Sendable, Equatable {
    public let level: Int
    public let wordCount: Int
    public let waitingCount: Int

    public init(level: Int, wordCount: Int, waitingCount: Int = 0) {
        self.level = level
        self.wordCount = wordCount
        self.waitingCount = waitingCount
    }
}

/// Decides which words come next and hands out sessions.
public final class SessionEngine {
    private let dbQueue: DatabaseQueue
    public let reviewLog: ReviewLog
    private let batchStore: BatchStore
    private let today: TodayProvider

    /// Where the shuffle in `startSession` gets its randomness (D17a). The
    /// app leaves this at the system generator; tests pass a seeded one so a
    /// draw is reproducible.
    private var rng: any RandomNumberGenerator

    public init(
        dbQueue: DatabaseQueue,
        today: TodayProvider = TodayProvider(),
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.dbQueue = dbQueue
        self.reviewLog = ReviewLog(dbQueue: dbQueue)
        self.batchStore = BatchStore(dbQueue: dbQueue)
        self.today = today
        self.rng = rng
    }

    /// The six levels in the catalogue, in level order, each with its total
    /// word count (the whole level, not what is left unseen) and how many
    /// words are waiting today. Recomputed fresh on every call, since a day
    /// rollover or a session held elsewhere can change the answer between
    /// calls.
    public func levelSummaries() throws -> [LevelSummary] {
        let now = today.today()
        return try dbQueue.read { db in
            let counts = try Row.fetchAll(
                db,
                sql: "SELECT level, COUNT(*) AS word_count FROM cat.word GROUP BY level ORDER BY level ASC;"
            )
            let waiting = try Row.fetchAll(
                db,
                sql: """
                SELECT b.level AS level, COUNT(*) AS waiting_count
                FROM batch b
                JOIN batch_word bw ON bw.batch_id = b.id
                WHERE b.next_look_on IS NOT NULL AND b.next_look_on <= ?
                GROUP BY b.level;
                """,
                arguments: [now]
            )
            let waitingByLevel = Dictionary(uniqueKeysWithValues: waiting.map { row in
                (row["level"] as Int, row["waiting_count"] as Int)
            })
            return counts.map { row in
                let level: Int = row["level"]
                return LevelSummary(
                    level: level,
                    wordCount: row["word_count"],
                    waitingCount: waitingByLevel[level] ?? 0
                )
            }
        }
    }

    /// Composes a session on `level`: every batch on `level` whose look is
    /// due on or before today, plus up to eight new words if the day's
    /// allowance hasn't been spent by another level (D5, D6, D7), all
    /// shuffled together into one pool (D6) with the injectable generator
    /// (D17a).
    ///
    /// A word counts as introduced once it belongs to any batch, not once a
    /// review row exists (D14) — a word parked by three left swipes is in
    /// its batch's `batch_word` rows already, so it is never drawn as new
    /// again. Neither the new batch nor any due batch's advance is written
    /// here: that happens on the session's first swipe (D3, D7).
    ///
    /// Returns a session with `drawnCount == 0` and `emptyReason` set when
    /// there is nothing to draw — see `Session.EmptyReason`.
    public func startSession(level: Int) throws -> Session {
        let dueBatches = try batchStore.dueBatches(level: level, today: today)
        let dueBatchIDs = dueBatches.compactMap(\.id)
        let dueWordIndices = try batchStore.wordIndices(batchIDs: dueBatchIDs)

        let unseenPool = try unseenWordIndices(level: level)

        let allowanceSpent = try batchStore.hasBatchCreatedToday(today: today)
        let newWordIndices = allowanceSpent ? [] : Array(unseenPool.shuffled(using: &rng).prefix(8))
        let hasUnseenWordsRemaining = unseenPool.count > newWordIndices.count

        var chosen = dueWordIndices + newWordIndices
        chosen.shuffle(using: &rng)

        guard !chosen.isEmpty else {
            let reason: Session.EmptyReason
            var nextBatchReturnOn: LocalDate?
            if !unseenPool.isEmpty {
                reason = .allowanceSpent
            } else if let earliest = try batchStore.earliestActiveLookOn(level: level) {
                reason = .waitingOnLadder
                nextBatchReturnOn = earliest
            } else {
                reason = .levelComplete
            }
            return Session(
                words: [], dbQueue: dbQueue, today: today, level: level,
                newWordIndices: [], dueBatchIDs: [], emptyReason: reason,
                hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nextBatchReturnOn
            )
        }

        let words = try words(forIndices: chosen)
        return Session(
            words: words, dbQueue: dbQueue, today: today, level: level,
            newWordIndices: newWordIndices, dueBatchIDs: dueBatchIDs, emptyReason: nil,
            hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nil
        )
    }

    /// Draws another eight new words on `level`, ignoring the day's
    /// allowance entirely — the "eight more" button's action. Holds no due
    /// batch, so its first swipe writes only a second batch on `level`
    /// dated today; nothing here advances a ladder.
    public func startBonusSession(level: Int) throws -> Session {
        let unseenPool = try unseenWordIndices(level: level)
        let newWordIndices = Array(unseenPool.shuffled(using: &rng).prefix(8))
        let hasUnseenWordsRemaining = unseenPool.count > newWordIndices.count

        let words = try words(forIndices: newWordIndices)
        return Session(
            words: words, dbQueue: dbQueue, today: today, level: level,
            newWordIndices: newWordIndices, dueBatchIDs: [], emptyReason: nil,
            hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nil
        )
    }

    /// Every word on `level` that belongs to no batch yet, as bare
    /// `word_index` values, in no particular order. Shuffling happens in
    /// Swift rather than with SQLite's `RANDOM()`, which is what makes a draw
    /// reproducible under a seeded generator; the pool is at most 1,800
    /// integers, so reading all of it costs nothing.
    private func unseenWordIndices(level: Int) throws -> [Int] {
        try dbQueue.read { db in
            try Int.fetchAll(
                db,
                sql: """
                SELECT w.word_index
                FROM cat.word w
                WHERE w.level = ?
                AND NOT EXISTS (SELECT 1 FROM batch_word bw WHERE bw.word_index = w.word_index);
                """,
                arguments: [level]
            )
        }
    }

    /// Fetches `indices` and puts them back in `indices`'s order — `IN`
    /// returns rows in whatever order SQLite likes, which would undo a
    /// caller's shuffle.
    private func words(forIndices indices: [Int]) throws -> [Word] {
        guard !indices.isEmpty else { return [] }
        let placeholders = databaseQuestionMarks(count: indices.count)
        let rows = try dbQueue.read { db in
            try Word.fetchAll(
                db,
                sql: """
                SELECT word_index, level, hanzi, pinyin, pinyin_numbered, definition
                FROM cat.word
                WHERE word_index IN (\(placeholders));
                """,
                arguments: StatementArguments(indices)
            )
        }
        let byIndex = Dictionary(uniqueKeysWithValues: rows.map { ($0.wordIndex, $0) })
        return indices.compactMap { byIndex[$0] }
    }
}
