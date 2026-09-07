import Foundation
import GRDB

/// A swipe's outcome (D16). A left swipe is `again`; a right swipe is `good`.
public enum Grade: String, Sendable, Codable, Equatable {
    case again
    case good
}

/// The append-only record of every swipe.
///
/// D16: a swipe writes one row holding `word_index`, a timestamp, and a
/// grade. D18: a word counts as introduced once any row here names its
/// `word_index` — there is no separate progress table. Nothing else reads
/// this table in this checkpoint.
public struct ReviewLog: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Records one swipe. Throws if the insert fails; a swipe that fails to
    /// write is not treated as recorded.
    public func record(wordIndex: Int, grade: Grade, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO review (word_index, reviewed_at, grade) VALUES (?, ?, ?);",
                arguments: [wordIndex, date.timeIntervalSince1970, grade.rawValue]
            )
        }
    }

    /// Whether `wordIndex` has ever been swiped, in any session (D18).
    public func isIntroduced(wordIndex: Int) throws -> Bool {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT 1 FROM review WHERE word_index = ? LIMIT 1;",
                arguments: [wordIndex]
            ) != nil
        }
    }
}
