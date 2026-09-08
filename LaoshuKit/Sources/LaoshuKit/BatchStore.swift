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
/// composite key — for the words the batch is carrying. Composing what a
/// session draws from this is the next task; this type only creates a
/// batch, looks it up, and moves it along `Batch`'s pure ladder.
public struct BatchStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Creates a batch on `level` holding `wordIndices`, scheduled per
    /// `BatchScheduler.createBatch(level:today:)`.
    @discardableResult
    public func createBatch(level: Int, wordIndices: [Int], today: TodayProvider) throws -> Batch {
        let batch = BatchScheduler.createBatch(level: level, today: today)

        return try dbQueue.write { db in
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
    }

    /// Records a look taken on this batch today, advancing it along the
    /// ladder (D2, D4). Throws if `batchID` names no row.
    @discardableResult
    public func recordLook(batchID: Int64, today: TodayProvider) throws -> Batch {
        try dbQueue.write { db in
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
    }

    public func fetchBatch(id: Int64) throws -> Batch? {
        try dbQueue.read { db in try Self.fetchBatch(db, id: id) }
    }

    /// Every batch due on `today`: not retired, and its next look is on or
    /// before today.
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
