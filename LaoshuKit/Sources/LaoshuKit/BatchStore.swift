import Foundation
import GRDB

public enum BatchStoreError: Error, CustomStringConvertible, Equatable {
    case batchNotFound(id: Int64)

    public var description: String {
        switch self {
        case .batchNotFound(let id):
            return "no batch with id \(id)"
        }
    }
}

/// Persists batches and the words each one holds: the `batch` table for the
/// ladder's own state, and `batch_word` — a `(batch_id, word_index)`
/// composite key — for the words the batch is carrying. `SessionEngine`
/// composes what a session draws from this; this type creates a batch,
/// looks it up, moves it along `Batch`'s pure ladder, and answers the
/// membership questions a draw needs (what's due, what's introduced, what's
/// spent the day's allowance).
public struct BatchStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Creates a batch on `level` holding `wordIndices`, scheduled per
    /// `BatchScheduler.createBatch(level:today:)`.
    @discardableResult
    public func createBatch(level: Int, wordIndices: [Int], today: TodayProvider) throws -> Batch {
        try dbQueue.write { db in
            try Self.createBatch(db, level: level, wordIndices: wordIndices, today: today)
        }
    }

    /// The raw insert, scoped to a `Database` already inside a transaction —
    /// what `Session.swipe` composes with the review row so a session's
    /// first swipe writes both in one transaction (D7, D7a).
    @discardableResult
    static func createBatch(_ db: Database, level: Int, wordIndices: [Int], today: TodayProvider) throws -> Batch {
        let batch = BatchScheduler.createBatch(level: level, today: today)

        try db.execute(
            sql: """
            INSERT INTO batch (level, created_on, next_look_on, look_number)
            VALUES (?, ?, ?, ?);
            """,
            arguments: [batch.level, batch.createdOn, batch.nextLookOn, batch.lookNumber]
        )
        let id = db.lastInsertedRowID

        for wordIndex in wordIndices {
            try db.execute(
                sql: "INSERT INTO batch_word (batch_id, word_index) VALUES (?, ?);",
                arguments: [id, wordIndex]
            )
        }

        var created = batch
        created.id = id
        return created
    }

    /// Records a look taken on this batch today, advancing it along the
    /// ladder (D2, D4). Throws if `batchID` names no row.
    @discardableResult
    public func recordLook(batchID: Int64, today: TodayProvider) throws -> Batch {
        try dbQueue.write { db in
            try Self.recordLook(db, batchID: batchID, today: today)
        }
    }

    /// The raw update, scoped to a `Database` already inside a
    /// transaction — see `createBatch(_:level:wordIndices:today:)`.
    @discardableResult
    static func recordLook(_ db: Database, batchID: Int64, today: TodayProvider) throws -> Batch {
        guard let batch = try Self.fetchBatch(db, id: batchID) else {
            throw BatchStoreError.batchNotFound(id: batchID)
        }

        let advanced = batch.lookTaken(on: today.today())
        try db.execute(
            sql: "UPDATE batch SET next_look_on = ?, look_number = ? WHERE id = ?;",
            arguments: [advanced.nextLookOn, advanced.lookNumber, batchID]
        )
        return advanced
    }

    /// Every word on `level` that belongs to no batch yet, as bare
    /// `word_index` values, in no particular order (D7c) — the pool a study
    /// session's new-word draw and the placement test's block draw both pull
    /// from, so a word already batched from either path can never be picked
    /// by the other.
    public func unseenWordIndices(level: Int) throws -> [Int] {
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

    /// Writes a batch that is already retired: dated `today`, holding
    /// `wordIndices`, with no look due and look number 2 (D10) — how the
    /// placement test records words answered "know it" so each is never
    /// taught as new again but is never looked at either.
    @discardableResult
    public func createRetiredBatch(level: Int, wordIndices: [Int], today: TodayProvider) throws -> Batch {
        try dbQueue.write { db in
            try Self.createRetiredBatch(db, level: level, wordIndices: wordIndices, today: today)
        }
    }

    /// The raw insert, scoped to a `Database` already inside a transaction —
    /// see `createBatch(_:level:wordIndices:today:)`.
    @discardableResult
    static func createRetiredBatch(_ db: Database, level: Int, wordIndices: [Int], today: TodayProvider) throws -> Batch {
        let batch = Batch(level: level, createdOn: today.today(), nextLookOn: nil, lookNumber: 2)

        try db.execute(
            sql: """
            INSERT INTO batch (level, created_on, next_look_on, look_number)
            VALUES (?, ?, ?, ?);
            """,
            arguments: [batch.level, batch.createdOn, batch.nextLookOn, batch.lookNumber]
        )
        let id = db.lastInsertedRowID

        for wordIndex in wordIndices {
            try db.execute(
                sql: "INSERT INTO batch_word (batch_id, word_index) VALUES (?, ?);",
                arguments: [id, wordIndex]
            )
        }

        var created = batch
        created.id = id
        return created
    }

    public func fetchBatch(id: Int64) throws -> Batch? {
        try dbQueue.read { db in try Self.fetchBatch(db, id: id) }
    }

    /// Every batch due on `today`, across all levels: not retired, and its
    /// next look is on or before today.
    public func dueBatches(today: TodayProvider) throws -> [Batch] {
        let now = today.today()
        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, level, created_on, next_look_on, look_number
                FROM batch
                WHERE next_look_on IS NOT NULL AND next_look_on <= ?
                ORDER BY next_look_on ASC;
                """,
                arguments: [now]
            ).map(Self.batch(from:))
        }
    }

    /// Every batch due on `today` on `level` — what a session's draw holds
    /// in full alongside the day's new words (D6).
    public func dueBatches(level: Int, today: TodayProvider) throws -> [Batch] {
        let now = today.today()
        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, level, created_on, next_look_on, look_number
                FROM batch
                WHERE level = ? AND next_look_on IS NOT NULL AND next_look_on <= ?
                ORDER BY next_look_on ASC;
                """,
                arguments: [level, now]
            ).map(Self.batch(from:))
        }
    }

    /// Every word held by any of `batchIDs`, unordered — a draw shuffles
    /// this together with the day's new words itself (D6).
    public func wordIndices(batchIDs: [Int64]) throws -> [Int] {
        guard !batchIDs.isEmpty else { return [] }
        let placeholders = databaseQuestionMarks(count: batchIDs.count)
        return try dbQueue.read { db in
            try Int.fetchAll(
                db,
                sql: "SELECT word_index FROM batch_word WHERE batch_id IN (\(placeholders));",
                arguments: StatementArguments(batchIDs)
            )
        }
    }

    /// Whether any level's daily allowance of eight new words has already
    /// been spent — a batch created today, on any level, that has not
    /// retired (D7, D6). `BatchScheduler.createBatch` always sets
    /// `next_look_on`, and `Batch.lookTaken` only nulls it on the second
    /// look, at least eight days later, so this exclusion cannot change the
    /// answer for any batch a study session actually created — only for a
    /// batch retired some other way, which must not still be spending
    /// today's allowance.
    public func hasBatchCreatedToday(today: TodayProvider) throws -> Bool {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT 1 FROM batch WHERE created_on = ? AND next_look_on IS NOT NULL LIMIT 1;",
                arguments: [today.today()]
            ) != nil
        }
    }

    /// Whether `level` has a batch still on the ladder — created, not yet
    /// retired, whether or not it is due today. Distinguishes a level that
    /// is fully introduced but still cycling through its looks from one that
    /// has nothing left to teach at all (D13).
    public func hasActiveBatch(level: Int) throws -> Bool {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT 1 FROM batch WHERE level = ? AND next_look_on IS NOT NULL LIMIT 1;",
                arguments: [level]
            ) != nil
        }
    }

    /// The soonest a still-active batch on `level` comes due, whether or not
    /// it is due yet — what the waiting-on-ladder empty state names as when
    /// the words come back.
    public func earliestActiveLookOn(level: Int) throws -> LocalDate? {
        try dbQueue.read { db in
            try LocalDate.fetchOne(
                db,
                sql: """
                SELECT next_look_on FROM batch
                WHERE level = ? AND next_look_on IS NOT NULL
                ORDER BY next_look_on ASC LIMIT 1;
                """,
                arguments: [level]
            )
        }
    }

    /// A word counts as introduced once it belongs to any batch (D14) —
    /// not when a review row exists, which would never be true of a word
    /// parked by three left swipes before its batch was written.
    public func isIntroduced(wordIndex: Int) throws -> Bool {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT 1 FROM batch_word WHERE word_index = ? LIMIT 1;",
                arguments: [wordIndex]
            ) != nil
        }
    }

    private static func fetchBatch(_ db: Database, id: Int64) throws -> Batch? {
        try Row.fetchOne(
            db,
            sql: "SELECT id, level, created_on, next_look_on, look_number FROM batch WHERE id = ?;",
            arguments: [id]
        ).map(batch(from:))
    }

    private static func batch(from row: Row) -> Batch {
        Batch(
            id: row["id"],
            level: row["level"],
            createdOn: row["created_on"],
            nextLookOn: row["next_look_on"],
            lookNumber: row["look_number"]
        )
    }
}
