import Foundation
import GRDB

/// The `placement` table's one row, read back as something a caller can
/// switch on rather than raw `status`/`recommended_level` columns (D13/D13a
/// in `LaoshuDatabase`).
public enum PlacementStatus: Sendable, Equatable {
    case notTaken
    /// The level is optional because a taken placement does not always carry
    /// one: D13a seeds a phone that already holds study as taken with no
    /// recommendation, since nothing recommended anything to it.
    case taken(recommendedLevel: Int?)
    case declined
}

/// Reads and writes the singleton `placement` row: whether the first-launch
/// gate has fired yet, and — once a test finishes or is declined — what it
/// decided.
public struct PlacementStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func status() throws -> PlacementStatus {
        try dbQueue.read { db in
            // No row at all should be unreachable, since the migration
            // writes one. Read as not taken rather than trapping: the cost
            // of being wrong is offering the test again, and this runs on
            // the first frame after launch, where a trap is a dead app.
            guard let row = try Row.fetchOne(
                db, sql: "SELECT status, recommended_level FROM placement WHERE id = 1;"
            ) else { return .notTaken }
            let status: String = row["status"]
            switch status {
            case "taken":
                return .taken(recommendedLevel: row["recommended_level"])
            case "declined":
                return .declined
            default:
                return .notTaken
            }
        }
    }

    /// Records the skip on the first screen: the gate must not fire again,
    /// and a declined test recommends nothing (the schema's own constraint).
    public func decline() throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE placement SET status = 'declined', recommended_level = NULL WHERE id = 1;")
        }
    }

    /// The raw update, scoped to a `Database` already inside a transaction —
    /// what `PlacementSession.finish` composes with the retired batches it
    /// writes, so a walk that finishes writes both in one transaction.
    static func markTaken(_ db: Database, recommendedLevel: Int) throws {
        try db.execute(
            sql: "UPDATE placement SET status = 'taken', recommended_level = ? WHERE id = 1;",
            arguments: [recommendedLevel]
        )
    }
}
