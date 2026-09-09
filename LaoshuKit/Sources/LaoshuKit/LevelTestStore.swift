import Foundation
import GRDB

/// One level test attempt: a level, when it was taken, and the raw score —
/// what `LevelTest` writes and what the finished-level screen reads back to
/// show the last result (route line 9).
public struct LevelTestResult: Sendable, Equatable {
    public let level: Int
    public let takenOn: LocalDate
    public let correctCount: Int
    public let totalCount: Int
    public let passed: Bool

    public init(level: Int, takenOn: LocalDate, correctCount: Int, totalCount: Int, passed: Bool) {
        self.level = level
        self.takenOn = takenOn
        self.correctCount = correctCount
        self.totalCount = totalCount
        self.passed = passed
    }

    public var percentCorrect: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(correctCount) / Double(totalCount) * 100).rounded())
    }
}

/// Persists the singleton-per-level `level_test` row. A level tested twice
/// keeps only the most recent attempt (D-shaped like `preference` and
/// `placement`: one row, overwritten, no history).
public struct LevelTestStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func record(_ attempt: LevelTestResult) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO level_test (level, taken_on, correct_count, total_count, passed)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (level) DO UPDATE SET
                    taken_on = excluded.taken_on,
                    correct_count = excluded.correct_count,
                    total_count = excluded.total_count,
                    passed = excluded.passed;
                """,
                arguments: [attempt.level, attempt.takenOn, attempt.correctCount, attempt.totalCount, attempt.passed ? 1 : 0]
            )
        }
    }

    public func result(level: Int) throws -> LevelTestResult? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT level, taken_on, correct_count, total_count, passed FROM level_test WHERE level = ?;",
                arguments: [level]
            ).map { row in
                LevelTestResult(
                    level: row["level"],
                    takenOn: row["taken_on"],
                    correctCount: row["correct_count"],
                    totalCount: row["total_count"],
                    passed: (row["passed"] as Int) == 1
                )
            }
        }
    }
}
