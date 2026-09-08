import Foundation
import GRDB

/// Replays review rows recorded before batches existed into batches, once
/// (D18, cashing in checkpoint 1's D16). Registered as a schema migration
/// (see `LaoshuDatabase`) so it inherits that mechanism's guarantees for
/// free: the replay and its completion marker land in one transaction, and
/// `DatabaseMigrator` never re-runs a migration it has already recorded.
enum ReviewLogReplay {
    private struct Group: Hashable {
        let day: LocalDate
        let level: Int
    }

    /// Groups every reviewed word by the pair of (the local day of its first
    /// review row, its level — D18's grouping key, since a batch carries
    /// exactly one level) and creates one batch per group, wound forward to
    /// where it would stand on `today`.
    static func run(db: Database, today: TodayProvider) throws {
        let wordRows = try Row.fetchAll(
            db,
            sql: """
            SELECT r.word_index AS word_index, w.level AS level, MIN(r.reviewed_at) AS first_reviewed_at
            FROM review r
            JOIN cat.word w ON w.word_index = r.word_index
            GROUP BY r.word_index;
            """
        )

        var wordIndicesByGroup: [Group: [Int]] = [:]
        for row in wordRows {
            let wordIndex: Int = row["word_index"]
            let level: Int = row["level"]
            let firstReviewedAt: Double = row["first_reviewed_at"]
            let day = today.businessDay(for: Date(timeIntervalSince1970: firstReviewedAt))
            wordIndicesByGroup[Group(day: day, level: level), default: []].append(wordIndex)
        }

        let todayDate = today.today()
        for (group, wordIndices) in wordIndicesByGroup {
            let batch = BatchScheduler.replayBatch(level: group.level, createdOn: group.day, today: todayDate)

            try db.execute(
                sql: """
                INSERT INTO batch (level, created_on, next_look_on, look_number)
                VALUES (?, ?, ?, ?);
                """,
                arguments: [batch.level, batch.createdOn, batch.nextLookOn, batch.lookNumber]
            )
            let batchID = db.lastInsertedRowID

            for wordIndex in wordIndices {
                try db.execute(
                    sql: "INSERT INTO batch_word (batch_id, word_index) VALUES (?, ?);",
                    arguments: [batchID, wordIndex]
                )
            }
        }
    }
}
