import Foundation
import GRDB
@testable import LaoshuKit

/// Builds a throwaway catalogue database with `count` level-1 words,
/// word_index 1...count, and points a fresh review log at a sibling file in
/// the same temporary directory — mirroring the shape `LaoshuDatabase.open`
/// expects, without touching the app bundle or Application Support.
enum TestFixtures {
    static func makeDatabase(wordCount: Int = 20, level: Int = 1) throws -> DatabaseQueue {
        try makeDatabase(levelCounts: [level: wordCount])
    }

    /// Builds a throwaway catalogue with one contiguous block of `word_index`
    /// per level, levels visited in ascending order, for tests that need more
    /// than one level present (e.g. the level list's per-level counts).
    static func makeDatabase(levelCounts: [Int: Int]) throws -> DatabaseQueue {
        let (directory, catalogueURL) = try makeCatalogue(levelCounts: levelCounts)
        let reviewLogURL = directory.appendingPathComponent("review.sqlite")
        return try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
    }

    /// Builds a throwaway catalogue database with one contiguous block of
    /// `word_index` per level, and returns its containing directory (for a
    /// caller to also place a review log in) alongside its URL.
    static func makeCatalogue(levelCounts: [Int: Int]) throws -> (directory: URL, catalogueURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let catalogueURL = directory.appendingPathComponent("catalogue.sqlite")
        let catalogueQueue = try DatabaseQueue(path: catalogueURL.path)
        try catalogueQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE word (
                    word_index INTEGER PRIMARY KEY,
                    level INTEGER NOT NULL,
                    hanzi TEXT NOT NULL,
                    pinyin TEXT NOT NULL,
                    pinyin_numbered TEXT NOT NULL,
                    definition TEXT NOT NULL
                );
                """)
            var index = 1
            for level in levelCounts.keys.sorted() {
                let count = levelCounts[level] ?? 0
                for _ in 0..<count {
                    try db.execute(
                        sql: """
                        INSERT INTO word (word_index, level, hanzi, pinyin, pinyin_numbered, definition)
                        VALUES (?, ?, ?, ?, ?, ?);
                        """,
                        arguments: [index, level, "字\(index)", "zi\(index)", "zi4\(index)", "word \(index)"]
                    )
                    index += 1
                }
            }
        }
        // Release the catalogue's own connection before the primary connection
        // opens it read-only; SQLite handles concurrent readers fine, but
        // nothing here needs the write handle open any longer.

        return (directory, catalogueURL)
    }

    /// Writes a review log already on the pre-batch schema (`review` table
    /// only) with the given rows already in it — what an app upgrading into
    /// this checkpoint finds on disk before its first launch replays it. The
    /// `v1_review_log` migration is applied for real, through GRDB's own
    /// migrator, rather than by hand: a real pre-upgrade database already has
    /// that migration recorded in `grdb_migrations`, and without that record
    /// `LaoshuDatabase.open`'s migrator would try to create the `review`
    /// table a second time. Callers then open the result for real through
    /// `LaoshuDatabase.open` to exercise the actual upgrade path.
    static func makePreUpgradeReviewLog(
        at reviewLogURL: URL,
        rows: [(wordIndex: Int, reviewedAt: Date, grade: Grade)]
    ) throws {
        // Built the way checkpoint 1 built it: bare statements, run
        // directly, with no `DatabaseMigrator` and so no `grdb_migrations`
        // table. Going through a migrator here would stamp v1 as applied
        // and hide the upgrade this fixture exists to reproduce.
        let dbQueue = try DatabaseQueue(path: reviewLogURL.path)
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS review (
                    word_index INTEGER NOT NULL,
                    reviewed_at REAL NOT NULL,
                    grade TEXT NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS review_word_index ON review(word_index);")
        }
        try dbQueue.write { db in
            for row in rows {
                try db.execute(
                    sql: "INSERT INTO review (word_index, reviewed_at, grade) VALUES (?, ?, ?);",
                    arguments: [row.wordIndex, row.reviewedAt.timeIntervalSince1970, row.grade.rawValue]
                )
            }
        }
    }

    /// Builds a review log on exactly the schema checkpoint 2 shipped —
    /// `review`, `batch`, `batch_word` — with the given batch (and its
    /// words) already on the ladder, and the three migrations that produce
    /// that schema recorded in `grdb_migrations` exactly as a real upgrading
    /// phone has them.
    ///
    /// The definitions here are copied by hand from checkpoint 2's shipped
    /// migrator rather than obtained by calling into `LaoshuDatabase`'s own
    /// (now placement-aware) migrator: a fixture built by the migrator under
    /// test would already have the placement table and a seeded row before
    /// the test ever opens it for real, proving nothing about the upgrade.
    /// This is the exact defect that shipped in checkpoint 2 (see commit
    /// 6b1b765) — a migration test whose fixture is built by the migrator
    /// under test proves nothing about upgrades.
    static func makeCheckpoint2ReviewLog(
        at reviewLogURL: URL,
        batches: [(level: Int, createdOn: LocalDate, nextLookOn: LocalDate?, lookNumber: Int, wordIndices: [Int])] = [],
        reviewRows: [(wordIndex: Int, reviewedAt: Date, grade: Grade)] = []
    ) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_review_log") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS review (
                    word_index INTEGER NOT NULL,
                    reviewed_at REAL NOT NULL,
                    grade TEXT NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS review_word_index ON review(word_index);")
        }
        migrator.registerMigration("v2_batch_tables") { db in
            try db.execute(sql: """
                CREATE TABLE batch (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    level INTEGER NOT NULL,
                    created_on TEXT NOT NULL,
                    next_look_on TEXT,
                    look_number INTEGER NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX batch_next_look_on ON batch(next_look_on);")
            try db.execute(sql: """
                CREATE TABLE batch_word (
                    batch_id INTEGER NOT NULL REFERENCES batch(id),
                    word_index INTEGER NOT NULL,
                    PRIMARY KEY (batch_id, word_index)
                );
                """)
        }
        migrator.registerMigration("v3_replay_review_log_into_batches") { _ in
            // Nothing to replay: this fixture writes batch rows directly
            // below, standing in for whatever the real replay produced.
        }

        let dbQueue = try DatabaseQueue(path: reviewLogURL.path)
        try migrator.migrate(dbQueue)

        try dbQueue.write { db in
            for row in reviewRows {
                try db.execute(
                    sql: "INSERT INTO review (word_index, reviewed_at, grade) VALUES (?, ?, ?);",
                    arguments: [row.wordIndex, row.reviewedAt.timeIntervalSince1970, row.grade.rawValue]
                )
            }
            for batch in batches {
                try db.execute(
                    sql: """
                    INSERT INTO batch (level, created_on, next_look_on, look_number)
                    VALUES (?, ?, ?, ?);
                    """,
                    arguments: [batch.level, batch.createdOn, batch.nextLookOn, batch.lookNumber]
                )
                let id = db.lastInsertedRowID
                for wordIndex in batch.wordIndices {
                    try db.execute(
                        sql: "INSERT INTO batch_word (batch_id, word_index) VALUES (?, ?);",
                        arguments: [id, wordIndex]
                    )
                }
            }
        }
        try dbQueue.close()
    }
}

/// A deterministic generator so a shuffled draw (D17a) is reproducible in
/// tests. SplitMix64, chosen because it is a few lines and its sequence does
/// not depend on the platform's random source.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension TestFixtures {
    /// An engine whose draw is reproducible. Every test that cares about
    /// which words come out uses this rather than the system generator.
    /// `today` defaults to the real clock; tests that need to control which
    /// day it is (batches due, the daily allowance) pass a fixed one.
    static func makeEngine(
        dbQueue: DatabaseQueue,
        seed: UInt64 = 42,
        today: TodayProvider = TodayProvider()
    ) -> SessionEngine {
        SessionEngine(dbQueue: dbQueue, today: today, rng: SeededGenerator(seed: seed))
    }
}
