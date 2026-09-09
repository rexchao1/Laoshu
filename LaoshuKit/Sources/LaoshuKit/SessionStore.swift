import Foundation
import GRDB

/// Whether a study session is still being worked, or how it ended.
public enum SessionStatus: String, Sendable, Equatable {
    case live
    case done
    case abandoned
}

/// How a card left the queue: swiped right after being revealed, or parked
/// by three left swipes.
public enum SessionCardOutcome: String, Sendable, Equatable {
    case finished
    case parked
}

/// One row of `session_card`. `position` is the card's place in the queue
/// and is `nil` once the card is settled (D5); `outcome` and `settledOrder`
/// are the reverse, `nil` while the card is still pending.
public struct StoredSessionCard: Sendable, Equatable {
    public let wordIndex: Int
    public var position: Int?
    public var leftSwipeCount: Int
    public var outcome: SessionCardOutcome?
    public var settledOrder: Int?

    public init(
        wordIndex: Int,
        position: Int?,
        leftSwipeCount: Int = 0,
        outcome: SessionCardOutcome? = nil,
        settledOrder: Int? = nil
    ) {
        self.wordIndex = wordIndex
        self.position = position
        self.leftSwipeCount = leftSwipeCount
        self.outcome = outcome
        self.settledOrder = settledOrder
    }
}

/// One row of `session`, with the cards it holds.
public struct StoredSession: Sendable, Equatable {
    public var id: Int64?
    public let level: Int
    public let createdOn: LocalDate
    public let direction: StudyDirection
    public let speakOnFlip: Bool
    public var newWordsBatchID: Int64?
    public var status: SessionStatus
    public var cards: [StoredSessionCard]

    public init(
        id: Int64? = nil,
        level: Int,
        createdOn: LocalDate,
        direction: StudyDirection,
        speakOnFlip: Bool,
        newWordsBatchID: Int64? = nil,
        status: SessionStatus,
        cards: [StoredSessionCard]
    ) {
        self.id = id
        self.level = level
        self.createdOn = createdOn
        self.direction = direction
        self.speakOnFlip = speakOnFlip
        self.newWordsBatchID = newWordsBatchID
        self.status = status
        self.cards = cards
    }
}

/// Persists a study session and the cards in its queue: the `session` table
/// for the session's own state, and `session_card` — a `(session_id,
/// word_index)` composite key — for the queue and what has settled out of
/// it. `Session` and `SessionEngine` write no SQL of their own; this type
/// owns every query against the two tables (D28).
public struct SessionStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Inserts `session` and every card it holds. `session.id` is ignored;
    /// the returned session carries the id SQLite assigned.
    ///
    /// Fails if `session.level` already holds a live session
    /// (`session_one_live_per_level`) or two of its cards claim the same
    /// position (`session_card_one_card_per_position`).
    @discardableResult
    public func insertSession(_ session: StoredSession) throws -> StoredSession {
        try dbQueue.write { db in
            try Self.insertSession(db, session)
        }
    }

    /// The raw insert, scoped to a `Database` already inside a transaction
    /// (D29) — the shape `BatchStore.createBatch(_:level:wordIndices:today:)`
    /// already takes, so a caller can write a session's first swipe and the
    /// batch it draws from in one transaction.
    @discardableResult
    static func insertSession(_ db: Database, _ session: StoredSession) throws -> StoredSession {
        try db.execute(
            sql: """
            INSERT INTO session (level, created_on, direction, speak_on_flip, new_words_batch_id, status)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            arguments: [
                session.level,
                session.createdOn,
                session.direction.rawValue,
                session.speakOnFlip ? 1 : 0,
                session.newWordsBatchID,
                session.status.rawValue,
            ]
        )
        let id = db.lastInsertedRowID

        for card in session.cards {
            try Self.insertCard(db, sessionID: id, card: card)
        }

        var created = session
        created.id = id
        return created
    }

    private static func insertCard(_ db: Database, sessionID: Int64, card: StoredSessionCard) throws {
        try db.execute(
            sql: """
            INSERT INTO session_card (session_id, word_index, position, left_swipe_count, outcome, settled_order)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            arguments: [
                sessionID,
                card.wordIndex,
                card.position,
                card.leftSwipeCount,
                card.outcome?.rawValue,
                card.settledOrder,
            ]
        )
    }

    /// `level`'s live session, with its cards ordered by `position` — the
    /// pending ones in queue order, the settled ones (`position` is `nil`)
    /// after them in `settledOrder`. `nil` if `level` holds no live session.
    public func liveSession(level: Int) throws -> StoredSession? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT id, level, created_on, direction, speak_on_flip, new_words_batch_id, status
                FROM session WHERE level = ? AND status = 'live';
                """,
                arguments: [level]
            ) else { return nil }

            let sessionID: Int64 = row["id"]
            let cardRows = try Row.fetchAll(
                db,
                sql: """
                SELECT word_index, position, left_swipe_count, outcome, settled_order
                FROM session_card
                WHERE session_id = ?
                ORDER BY position IS NULL, position ASC, settled_order ASC;
                """,
                arguments: [sessionID]
            )

            return Self.session(from: row, cards: cardRows.map(Self.card(from:)))
        }
    }

    /// Settles `wordIndex` out of `sessionID`'s queue: clears its position
    /// and records `outcome`. `settledOrder` is computed in this same
    /// statement as `MAX(settled_order) + 1` over the session's own rows,
    /// starting at 0 when there are none (D5c), so two settles racing inside
    /// the same transaction can never collide.
    public func settleCard(sessionID: Int64, wordIndex: Int, outcome: SessionCardOutcome) throws {
        try dbQueue.write { db in
            try Self.settleCard(db, sessionID: sessionID, wordIndex: wordIndex, outcome: outcome)
        }
    }

    static func settleCard(_ db: Database, sessionID: Int64, wordIndex: Int, outcome: SessionCardOutcome) throws {
        try db.execute(
            sql: """
            UPDATE session_card
            SET position = NULL,
                outcome = ?,
                settled_order = (
                    SELECT COALESCE(MAX(settled_order), -1) + 1
                    FROM session_card WHERE session_id = ?
                )
            WHERE session_id = ? AND word_index = ?;
            """,
            arguments: [outcome.rawValue, sessionID, sessionID, wordIndex]
        )
    }

    /// Records a left swipe that did not settle the card: `wordIndex` stays
    /// pending (`outcome` untouched, still null), only `left_swipe_count`
    /// moves. Position is left for `rewritePendingPositions` to set.
    public func recordLeftSwipe(sessionID: Int64, wordIndex: Int, leftSwipeCount: Int) throws {
        try dbQueue.write { db in
            try Self.recordLeftSwipe(db, sessionID: sessionID, wordIndex: wordIndex, leftSwipeCount: leftSwipeCount)
        }
    }

    static func recordLeftSwipe(_ db: Database, sessionID: Int64, wordIndex: Int, leftSwipeCount: Int) throws {
        try db.execute(
            sql: "UPDATE session_card SET left_swipe_count = ? WHERE session_id = ? AND word_index = ?;",
            arguments: [leftSwipeCount, sessionID, wordIndex]
        )
    }

    /// Rewrites `sessionID`'s pending queue to `order`, position `0` first.
    /// Every still-pending card not named in `order` is dropped from the
    /// queue (position set to `nil`) — a caller passes the full queue it
    /// wants, not a delta.
    ///
    /// Every position is cleared before any of `order` is written, so a
    /// queue reshuffling in place (item 3 moving to slot 0) never trips
    /// `session_card_one_card_per_position` on a position it is only
    /// passing through.
    public func rewritePendingPositions(sessionID: Int64, order: [Int]) throws {
        try dbQueue.write { db in
            try Self.rewritePendingPositions(db, sessionID: sessionID, order: order)
        }
    }

    static func rewritePendingPositions(_ db: Database, sessionID: Int64, order: [Int]) throws {
        try db.execute(
            sql: "UPDATE session_card SET position = NULL WHERE session_id = ? AND position IS NOT NULL;",
            arguments: [sessionID]
        )
        for (position, wordIndex) in order.enumerated() {
            try db.execute(
                sql: "UPDATE session_card SET position = ? WHERE session_id = ? AND word_index = ?;",
                arguments: [position, sessionID, wordIndex]
            )
        }
    }

    /// Sets `sessionID`'s own status — `live` to `done` once the queue is
    /// empty, or to `abandoned` when a new session replaces it.
    public func setStatus(sessionID: Int64, status: SessionStatus) throws {
        try dbQueue.write { db in
            try Self.setStatus(db, sessionID: sessionID, status: status)
        }
    }

    static func setStatus(_ db: Database, sessionID: Int64, status: SessionStatus) throws {
        try db.execute(
            sql: "UPDATE session SET status = ? WHERE id = ?;",
            arguments: [status.rawValue, sessionID]
        )
    }

    private static func session(from row: Row, cards: [StoredSessionCard]) -> StoredSession {
        let direction: String = row["direction"]
        let status: String = row["status"]
        return StoredSession(
            id: row["id"],
            level: row["level"],
            createdOn: row["created_on"],
            direction: StudyDirection(rawValue: direction) ?? .receptive,
            speakOnFlip: (row["speak_on_flip"] as Int) == 1,
            newWordsBatchID: row["new_words_batch_id"],
            status: SessionStatus(rawValue: status) ?? .live,
            cards: cards
        )
    }

    private static func card(from row: Row) -> StoredSessionCard {
        let outcome: String? = row["outcome"]
        return StoredSessionCard(
            wordIndex: row["word_index"],
            position: row["position"],
            leftSwipeCount: row["left_swipe_count"],
            outcome: outcome.flatMap(SessionCardOutcome.init(rawValue:)),
            settledOrder: row["settled_order"]
        )
    }
}
