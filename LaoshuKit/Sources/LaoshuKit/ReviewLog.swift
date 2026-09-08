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
/// grade. D15: nothing schedules from this table — a word's introduced
/// status is decided by batch membership (`BatchStore.isIntroduced`), not by
/// a row here.
public struct ReviewLog: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Records one swipe. Throws if the insert fails; a swipe that fails to
    /// write is not treated as recorded.
    public func record(wordIndex: Int, grade: Grade, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try Self.record(db, wordIndex: wordIndex, grade: grade, at: date)
        }
    }

    /// The raw insert, scoped to a `Database` already inside a transaction —
    /// what `Session.swipe` composes with the batch write so both land in
    /// the same transaction.
    static func record(_ db: Database, wordIndex: Int, grade: Grade, at date: Date) throws {
        try db.execute(
            sql: "INSERT INTO review (word_index, reviewed_at, grade) VALUES (?, ?, ?);",
            arguments: [wordIndex, date.timeIntervalSince1970, grade.rawValue]
        )
    }
}
