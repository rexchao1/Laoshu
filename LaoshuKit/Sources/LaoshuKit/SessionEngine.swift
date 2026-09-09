import Foundation
import GRDB
import Observation

/// Which way a card was swiped.
public enum SwipeDirection: Sendable {
    case left
    case right
}

/// One of a card's two faces: the Chinese side (pinyin and hanzi, with its
/// spoken audio — D6a leaves where those sit inside this face to the view)
/// or the meaning alone.
public enum CardFace: Sendable, Equatable {
    case chinese
    case meaning
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

    /// Which face asks and which answers, fixed by the session's direction
    /// at the draw (D2, D3). The view renders a face given its kind and
    /// never branches on the direction itself (D6a).
    public let promptFace: CardFace
    public let answerFace: CardFace

    public private(set) var leftSwipeCount = 0
    public private(set) var isFlipped = false

    /// Whether the meaning has been shown at least once in this presentation.
    public private(set) var hasBeenRevealed = false

    init(word: Word, direction: StudyDirection, leftSwipeCount: Int = 0) {
        self.word = word
        switch direction {
        case .receptive:
            promptFace = .chinese
            answerFace = .meaning
        case .reverse:
            promptFace = .meaning
            answerFace = .chinese
        }
        self.leftSwipeCount = leftSwipeCount
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
/// Every swipe after the session's first also rewrites the queue's order and
/// each card's left-swipe count into `session` and `session_card` (D2), so a
/// session closed mid-queue and reopened on the same business day resumes
/// exactly where the swiping left it — see
/// `SessionEngine.startSession(level:)`. Before the first swipe nothing is
/// written at all (below), so closing the app before then leaves no trace
/// and the swipes already logged to `ReviewLog` stand regardless.
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

    /// Nil until the first swipe writes the `session` row, except for a
    /// resumed session, which already has one (D30).
    public private(set) var sessionID: Int64?

    /// Whether this session was handed back by `startSession(level:)` as an
    /// existing live row rather than freshly drawn (D30).
    public private(set) var isResumed = false

    private var queue: [Card]

    /// Which way this session asks, captured once at the draw and fixed for
    /// its lifetime (D2, D3): every card in `queue` is built from this same
    /// value, so a session's direction cannot change once it has started.
    public let direction: StudyDirection

    /// The `new_words_per_day` setting as it stood at the draw — not the
    /// count of new words the draw actually took, which can fall short when
    /// the level runs out of unseen words (D13c).
    public let newWordsPerDay: Int

    /// The `speak_on_flip` setting as it stood at the draw.
    public let speakOnFlip: Bool

    /// How many words this session actually drew: every due batch's words
    /// plus up to `newWordsPerDay` new ones (D6), unless the level had fewer
    /// of either left (D20).
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
    /// look, or `nil` when the session introduced none. Set at the draw as a
    /// preview computed the same way `BatchScheduler.createBatch` schedules
    /// it (D24), then overwritten on the first swipe with the `nextLookOn`
    /// of the `Batch` `BatchStore.createBatch` actually returns (D8) — the
    /// two agree unless the first swipe crosses midnight between the draw
    /// and the write.
    public private(set) var newWordsReturnOn: LocalDate?

    /// Whether the level still has unseen words left after this session's
    /// own draw — what decides whether the "eight more" button appears.
    public let hasUnseenWordsRemaining: Bool

    /// When the level's next active batch comes back, set only for the
    /// `.waitingOnLadder` empty reason.
    public let nextBatchReturnOn: LocalDate?

    /// Everything a resumed session needs beyond what a fresh draw computes:
    /// the queue and every count rebuilt from `session_card` (D6), and the
    /// row it came from (D30).
    struct ResumeData {
        let sessionID: Int64
        let queue: [Card]
        let drawnCount: Int
        let finishedCount: Int
        let parkedCount: Int
        let firstAttemptRightCount: Int
        let parkedWords: [Word]
        let newWordsReturnOn: LocalDate?
    }

    init(
        words: [Word],
        dbQueue: DatabaseQueue,
        today: TodayProvider,
        level: Int,
        newWordIndices: [Int],
        dueBatchIDs: [Int64],
        direction: StudyDirection,
        newWordsPerDay: Int,
        speakOnFlip: Bool,
        emptyReason: EmptyReason? = nil,
        hasUnseenWordsRemaining: Bool = false,
        nextBatchReturnOn: LocalDate? = nil,
        resumed resumeData: ResumeData? = nil
    ) {
        self.dbQueue = dbQueue
        self.today = today
        self.level = level
        self.newWordIndices = newWordIndices
        self.dueBatchIDs = dueBatchIDs
        self.direction = direction
        self.newWordsPerDay = newWordsPerDay
        self.speakOnFlip = speakOnFlip
        self.emptyReason = emptyReason
        self.hasUnseenWordsRemaining = hasUnseenWordsRemaining
        self.nextBatchReturnOn = nextBatchReturnOn

        if let resumeData {
            self.queue = resumeData.queue
            self.drawnCount = resumeData.drawnCount
            self.finishedCount = resumeData.finishedCount
            self.parkedCount = resumeData.parkedCount
            self.firstAttemptRightCount = resumeData.firstAttemptRightCount
            self.parkedWords = resumeData.parkedWords
            self.newWordsReturnOn = resumeData.newWordsReturnOn
            self.sessionID = resumeData.sessionID
            self.hasWrittenFirstSwipe = true
            self.isResumed = true
        } else {
            self.queue = words.map { Card(word: $0, direction: direction) }
            self.drawnCount = words.count
            self.newWordsReturnOn = newWordIndices.isEmpty
                ? nil
                : BatchScheduler.createBatch(level: level, today: today).nextLookOn
        }
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
    /// The first swipe of a session also writes the `session` row and every
    /// `session_card` row it holds, the batch of new words it drew (if any),
    /// and advances every due batch it drew from, all inside the same
    /// transaction as this swipe's review row (D7, D7a, D11). Every swipe —
    /// the first included — settles or requeues the card and rebuilds the
    /// pending queue as local values before writing anything (D11b, D12a),
    /// so a write that throws leaves `queue` and every count exactly as they
    /// were: nothing here is committed to `self` until the transaction
    /// succeeds.
    public func swipe(_ direction: SwipeDirection) throws {
        guard !queue.isEmpty else { return }
        let outgoing = queue[0]
        let rest = Array(queue.dropFirst())
        let grade: Grade = direction == .right ? .good : .again

        var settled: (card: Card, outcome: SessionCardOutcome)?
        var requeuedCard: Card?
        let pendingAfter: [Card]

        switch direction {
        case .right:
            settled = (outgoing, .finished)
            pendingAfter = rest

        case .left:
            var requeued = outgoing
            requeued.requeued()
            if requeued.leftSwipeCount >= 3 {
                settled = (requeued, .parked)
                pendingAfter = rest
            } else {
                requeuedCard = requeued
                var after = rest
                after.insert(requeued, at: min(3, rest.count))
                pendingAfter = after
            }
        }

        var createdBatch: Batch?
        var insertedSessionID: Int64?

        try dbQueue.write { db in
            try ReviewLog.record(db, wordIndex: outgoing.word.wordIndex, grade: grade, at: Date())

            if !self.hasWrittenFirstSwipe {
                if !self.newWordIndices.isEmpty {
                    createdBatch = try BatchStore.createBatch(db, level: self.level, wordIndices: self.newWordIndices, today: self.today)
                }
                for batchID in self.dueBatchIDs {
                    try BatchStore.recordLook(db, batchID: batchID, today: self.today)
                }

                let stored = StoredSession(
                    level: self.level,
                    createdOn: self.today.today(),
                    direction: self.direction,
                    speakOnFlip: self.speakOnFlip,
                    newWordsBatchID: createdBatch?.id,
                    status: pendingAfter.isEmpty ? .done : .live,
                    cards: self.initialStoredCards(pendingAfter: pendingAfter, settled: settled)
                )
                insertedSessionID = try SessionStore.insertSession(db, stored).id
            } else {
                let sessionID = self.sessionID!
                if let settled {
                    try SessionStore.settleCard(db, sessionID: sessionID, wordIndex: settled.card.word.wordIndex, outcome: settled.outcome)
                } else if let requeuedCard {
                    try SessionStore.recordLeftSwipe(db, sessionID: sessionID, wordIndex: requeuedCard.word.wordIndex, leftSwipeCount: requeuedCard.leftSwipeCount)
                }
                try SessionStore.rewritePendingPositions(db, sessionID: sessionID, order: pendingAfter.map(\.word.wordIndex))
                if pendingAfter.isEmpty {
                    try SessionStore.setStatus(db, sessionID: sessionID, status: .done)
                }
            }
        }

        if !hasWrittenFirstSwipe {
            hasWrittenFirstSwipe = true
            sessionID = insertedSessionID
            if let createdBatch {
                newWordsReturnOn = createdBatch.nextLookOn
            }
        }

        queue = pendingAfter
        switch direction {
        case .right:
            finishedCount += 1
            if outgoing.leftSwipeCount == 0 {
                firstAttemptRightCount += 1
            }

        case .left:
            if let settled {
                parkedCount += 1
                parkedWords.append(settled.card.word)
            }
        }
    }

    /// The full `session_card` row set for the session's first swipe: every
    /// card as originally drawn (`queue`, still untouched at this point),
    /// overlaid with `pendingAfter`'s positions for every card still pending
    /// and with `settled`'s outcome for the one this swipe settled, if any —
    /// the D5a position rewrite collapsed into a single insert since there
    /// is nothing yet to rewrite.
    private func initialStoredCards(
        pendingAfter: [Card],
        settled: (card: Card, outcome: SessionCardOutcome)?
    ) -> [StoredSessionCard] {
        var byWordIndex: [Int: StoredSessionCard] = [:]
        for card in queue {
            byWordIndex[card.word.wordIndex] = StoredSessionCard(wordIndex: card.word.wordIndex, position: nil, leftSwipeCount: card.leftSwipeCount)
        }
        for (position, card) in pendingAfter.enumerated() {
            byWordIndex[card.word.wordIndex] = StoredSessionCard(wordIndex: card.word.wordIndex, position: position, leftSwipeCount: card.leftSwipeCount)
        }
        if let settled {
            byWordIndex[settled.card.word.wordIndex] = StoredSessionCard(
                wordIndex: settled.card.word.wordIndex,
                position: nil,
                leftSwipeCount: settled.card.leftSwipeCount,
                outcome: settled.outcome,
                settledOrder: 0
            )
        }
        return queue.map { byWordIndex[$0.word.wordIndex]! }
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

/// Why `SessionEngine.browse(level:)` found nothing to list.
public enum BrowseEmptyReason: Sendable, Equatable {
    /// The level has no batch at all — nothing has ever been introduced.
    case levelHasNoBatches
}

/// Every word already met in a level, for the browse screen (D2, D3, D7,
/// D8, D10, D11).
public struct BrowseResult: Sendable, Equatable {
    public let words: [Word]
    public let emptyReason: BrowseEmptyReason?

    public init(words: [Word], emptyReason: BrowseEmptyReason? = nil) {
        self.words = words
        self.emptyReason = emptyReason
    }
}

/// Decides which words come next and hands out sessions.
public final class SessionEngine {
    private let dbQueue: DatabaseQueue
    public let reviewLog: ReviewLog
    private let batchStore: BatchStore
    private let preferenceStore: PreferenceStore
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
        self.preferenceStore = PreferenceStore(dbQueue: dbQueue)
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
        let preferences = try preferenceStore.preferences()
        let sessionStore = SessionStore(dbQueue: dbQueue)

        if let live = try sessionStore.liveSession(level: level), let liveID = live.id {
            if live.createdOn == today.today(),
                let resumed = try resumeSession(live, sessionID: liveID, preferences: preferences) {
                return resumed
            }
            try sessionStore.setStatus(sessionID: liveID, status: .abandoned)
        }

        let dueBatches = try batchStore.dueBatches(level: level, today: today)
        let dueBatchIDs = dueBatches.compactMap(\.id)
        let dueWordIndices = try batchStore.wordIndices(batchIDs: dueBatchIDs)

        let unseenPool = try batchStore.unseenWordIndices(level: level)

        let allowanceSpent = try batchStore.hasBatchCreatedToday(today: today)
        let newWordIndices = allowanceSpent ? [] : Array(unseenPool.shuffled(using: &rng).prefix(preferences.newWordsPerDay))
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
                newWordIndices: [], dueBatchIDs: [], direction: preferences.direction,
                newWordsPerDay: preferences.newWordsPerDay, speakOnFlip: preferences.speakOnFlip,
                emptyReason: reason,
                hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nextBatchReturnOn
            )
        }

        let words = try Word.fetch(indices: chosen, dbQueue: dbQueue)
        return Session(
            words: words, dbQueue: dbQueue, today: today, level: level,
            newWordIndices: newWordIndices, dueBatchIDs: dueBatchIDs, direction: preferences.direction,
            newWordsPerDay: preferences.newWordsPerDay, speakOnFlip: preferences.speakOnFlip,
            emptyReason: nil,
            hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nil
        )
    }

    /// Rebuilds a live `session` row into a resumable `Session`: the same
    /// queue in the same order with each card's left-swipe count intact, and
    /// every count rebuilt from `session_card` rather than stored anywhere
    /// (D2, D6, D10). Returns `nil` — asking the caller to abandon the row
    /// and draw fresh instead — when the row holds no cards, or when the
    /// words it names no longer resolve against the catalogue.
    private func resumeSession(_ stored: StoredSession, sessionID: Int64, preferences: Preferences) throws -> Session? {
        guard !stored.cards.isEmpty else { return nil }

        let pendingCards = stored.cards
            .filter { $0.position != nil }
            .sorted { $0.position! < $1.position! }
        let settledCards = stored.cards
            .filter { $0.outcome != nil }
            .sorted { ($0.settledOrder ?? 0) < ($1.settledOrder ?? 0) }

        let pendingWordIndices = pendingCards.map(\.wordIndex)
        let pendingWords = try Word.fetch(indices: pendingWordIndices, dbQueue: dbQueue)
        guard pendingWords.count == pendingWordIndices.count else { return nil }

        let settledWordIndices = settledCards.map(\.wordIndex)
        let settledWords = try Word.fetch(indices: settledWordIndices, dbQueue: dbQueue)
        guard settledWords.count == settledWordIndices.count else { return nil }
        let settledByIndex = Dictionary(uniqueKeysWithValues: zip(settledWordIndices, settledWords))

        let queue = zip(pendingCards, pendingWords).map { card, word in
            Card(word: word, direction: stored.direction, leftSwipeCount: card.leftSwipeCount)
        }

        let finishedCount = stored.cards.filter { $0.outcome == .finished }.count
        let parkedCount = stored.cards.filter { $0.outcome == .parked }.count
        let firstAttemptRightCount = stored.cards.filter { $0.outcome == .finished && $0.leftSwipeCount == 0 }.count
        let parkedWords = settledCards
            .filter { $0.outcome == .parked }
            .compactMap { settledByIndex[$0.wordIndex] }

        let hasUnseenWordsRemaining = try batchStore.unseenWordIndices(level: stored.level).isEmpty == false

        var newWordsReturnOn: LocalDate?
        if let batchID = stored.newWordsBatchID {
            newWordsReturnOn = try batchStore.fetchBatch(id: batchID)?.nextLookOn
        }

        let resumeData = Session.ResumeData(
            sessionID: sessionID,
            queue: queue,
            drawnCount: stored.cards.count,
            finishedCount: finishedCount,
            parkedCount: parkedCount,
            firstAttemptRightCount: firstAttemptRightCount,
            parkedWords: parkedWords,
            newWordsReturnOn: newWordsReturnOn
        )

        return Session(
            words: [], dbQueue: dbQueue, today: today, level: stored.level,
            newWordIndices: [], dueBatchIDs: [], direction: stored.direction,
            newWordsPerDay: preferences.newWordsPerDay, speakOnFlip: stored.speakOnFlip,
            emptyReason: nil,
            hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nil,
            resumed: resumeData
        )
    }

    /// Draws another eight new words on `level`, ignoring the day's
    /// allowance entirely — the "eight more" button's action. Holds no due
    /// batch, so its first swipe writes only a second batch on `level`
    /// dated today; nothing here advances a ladder.
    public func startBonusSession(level: Int) throws -> Session {
        let preferences = try preferenceStore.preferences()
        let unseenPool = try batchStore.unseenWordIndices(level: level)
        let newWordIndices = Array(unseenPool.shuffled(using: &rng).prefix(preferences.newWordsPerDay))
        let hasUnseenWordsRemaining = unseenPool.count > newWordIndices.count

        // The button that calls this is hidden when a level has no unseen
        // words (D19, D22), so an empty pool should not reach here. Nothing
        // in this API enforces that, though, and returning a drawn count of
        // zero with no reason renders "0 of 0 right the first time" — the
        // one screen D22 exists to remove. Name the reason instead.
        guard !newWordIndices.isEmpty else {
            let reason: Session.EmptyReason
            var nextBatchReturnOn: LocalDate?
            if let earliest = try batchStore.earliestActiveLookOn(level: level) {
                reason = .waitingOnLadder
                nextBatchReturnOn = earliest
            } else {
                reason = .levelComplete
            }
            return Session(
                words: [], dbQueue: dbQueue, today: today, level: level,
                newWordIndices: [], dueBatchIDs: [], direction: preferences.direction,
                newWordsPerDay: preferences.newWordsPerDay, speakOnFlip: preferences.speakOnFlip,
                emptyReason: reason,
                hasUnseenWordsRemaining: false, nextBatchReturnOn: nextBatchReturnOn
            )
        }

        let words = try Word.fetch(indices: newWordIndices, dbQueue: dbQueue)
        return Session(
            words: words, dbQueue: dbQueue, today: today, level: level,
            newWordIndices: newWordIndices, dueBatchIDs: [], direction: preferences.direction,
            newWordsPerDay: preferences.newWordsPerDay, speakOnFlip: preferences.speakOnFlip,
            emptyReason: nil,
            hasUnseenWordsRemaining: hasUnseenWordsRemaining, nextBatchReturnOn: nil
        )
    }

    /// Every word already met in `level`: every word belonging to any batch
    /// of the level, retired batches included (D3) — the whole of what the
    /// browse screen shows, and nothing else, since browsing never writes
    /// anything.
    ///
    /// Ordered by the batch's `created_on` descending, then the batch's `id`
    /// descending (D7 — `created_on` is a date, not a timestamp, so two
    /// batches created the same day need `id` to break the tie), then
    /// `word_index` ascending within a batch.
    ///
    /// Carries `emptyReason` rather than a bare empty array when the level
    /// has no batches at all.
    public func browse(level: Int) throws -> BrowseResult {
        let words = try dbQueue.read { db in
            try Word.fetchAll(
                db,
                sql: """
                SELECT w.word_index, w.level, w.hanzi, w.pinyin, w.pinyin_numbered, w.definition, w.gloss
                FROM batch b
                JOIN batch_word bw ON bw.batch_id = b.id
                JOIN cat.word w ON w.word_index = bw.word_index
                WHERE b.level = ?
                ORDER BY b.created_on DESC, b.id DESC, bw.word_index ASC;
                """,
                arguments: [level]
            )
        }

        if words.isEmpty {
            let hasBatches = try dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT 1 FROM batch WHERE level = ? LIMIT 1;",
                    arguments: [level]
                ) != nil
            }
            if !hasBatches {
                return BrowseResult(words: [], emptyReason: .levelHasNoBatches)
            }
        }

        return BrowseResult(words: words)
    }

    /// Starts a placement test (D1): the walk begins at level 2, drawing
    /// each block from the same unseen pool `startSession` draws from
    /// (D7c). On finishing, it writes a retired batch per level with words
    /// answered "know it" (D10).
    public func startPlacementTest() throws -> PlacementSession {
        try PlacementSession(dbQueue: dbQueue, batchStore: batchStore, today: today, rng: rng)
    }

    /// Whether the first-launch gate should fire, and what a test already
    /// taken or declined decided (D13/D13a).
    public func placementStatus() throws -> PlacementStatus {
        try PlacementStore(dbQueue: dbQueue).status()
    }

    /// Records the skip on the placement test's first screen so the gate
    /// never fires again.
    public func declinePlacementTest() throws {
        try PlacementStore(dbQueue: dbQueue).decline()
    }
}
