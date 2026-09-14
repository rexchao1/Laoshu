import Foundation
import GRDB

/// A level's standing through its own words: how many are learned, in
/// progress, left untouched, and waiting today (D10, D10a, D12, D13, D14,
/// D16). `learnedCount + inProgressCount + leftCount == wordCount` always;
/// `waitingCount` is a subset of `inProgressCount`, not added to it.
public struct LevelProgress: Sendable, Equatable {
    public let level: Int
    public let wordCount: Int
    public let learnedCount: Int
    public let inProgressCount: Int
    public let leftCount: Int
    public let waitingCount: Int

    public init(
        level: Int,
        wordCount: Int,
        learnedCount: Int,
        inProgressCount: Int,
        leftCount: Int,
        waitingCount: Int
    ) {
        self.level = level
        self.wordCount = wordCount
        self.learnedCount = learnedCount
        self.inProgressCount = inProgressCount
        self.leftCount = leftCount
        self.waitingCount = waitingCount
    }
}

/// Reads how far each level has come, for the progress screen (a later
/// checkpoint task). A pure read of the batch tables `SessionEngine` already
/// writes: nothing here schedules a batch or touches the ladder.
public struct ProgressStore: Sendable {
    private let dbQueue: DatabaseQueue
    private let today: TodayProvider

    public init(dbQueue: DatabaseQueue, today: TodayProvider = TodayProvider()) {
        self.dbQueue = dbQueue
        self.today = today
    }

    /// Every level in level order, each with its word count and the four
    /// counts D10 through D16 define. Recomputed fresh on every call, since a
    /// day rollover can change which words are waiting.
    ///
    /// D10, D10a: a word is learned once it belongs to no batch whose
    /// `next_look_on` is not NULL — whichever of `Batch.lookTaken` or
    /// `Batch.retiredForStaleness` wrote that NULL, and regardless of how
    /// many other retired batches also carry the word (D16). D12: a word
    /// with no batch at all is left. D13: waiting counts a word once, over
    /// batches whose look is due today. Missed looks from earlier days are
    /// not waiting. D14: waiting is a subset of in progress, never added to it.
    public func progress() throws -> [LevelProgress] {
        let now = today.today()
        return try dbQueue.read { db in
            let counts = try Row.fetchAll(
                db,
                sql: "SELECT level, COUNT(*) AS word_count FROM cat.word GROUP BY level ORDER BY level ASC;"
            )

            let wordStatus = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    b.level AS level,
                    bw.word_index AS word_index,
                    MAX(CASE WHEN b.next_look_on IS NOT NULL THEN 1 ELSE 0 END) AS has_active,
                    MAX(CASE WHEN b.next_look_on IS NOT NULL AND b.next_look_on = ? THEN 1 ELSE 0 END) AS is_waiting
                FROM batch_word bw
                JOIN batch b ON b.id = bw.batch_id
                GROUP BY b.level, bw.word_index;
                """,
                arguments: [now]
            )

            var learnedByLevel: [Int: Int] = [:]
            var inProgressByLevel: [Int: Int] = [:]
            var waitingByLevel: [Int: Int] = [:]
            for row in wordStatus {
                let level: Int = row["level"]
                let hasActive: Int = row["has_active"]
                let isWaiting: Int = row["is_waiting"]
                if hasActive == 1 {
                    inProgressByLevel[level, default: 0] += 1
                } else {
                    learnedByLevel[level, default: 0] += 1
                }
                if isWaiting == 1 {
                    waitingByLevel[level, default: 0] += 1
                }
            }

            return counts.map { row in
                let level: Int = row["level"]
                let wordCount: Int = row["word_count"]
                let learnedCount = learnedByLevel[level] ?? 0
                let inProgressCount = inProgressByLevel[level] ?? 0
                return LevelProgress(
                    level: level,
                    wordCount: wordCount,
                    learnedCount: learnedCount,
                    inProgressCount: inProgressCount,
                    leftCount: wordCount - learnedCount - inProgressCount,
                    waitingCount: waitingByLevel[level] ?? 0
                )
            }
        }
    }
}
