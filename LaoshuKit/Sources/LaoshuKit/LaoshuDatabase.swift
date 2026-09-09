import Foundation
import GRDB

public enum LaoshuDatabaseError: Error, CustomStringConvertible, Equatable {
    case catalogueNotFound(path: String)

    public var description: String {
        switch self {
        case .catalogueNotFound(let path):
            return "no catalogue database at \(path)"
        }
    }
}

/// Opens the one connection every query in the app runs on.
///
/// D23: the writable review log is the primary connection, opened first.
/// The read-only bundled catalogue is then `ATTACH`ed to it as schema `cat`.
/// A read-only connection cannot log a swipe, so the catalogue can never be
/// the primary connection.
public enum LaoshuDatabase {
    /// Opens the review log at `reviewLogURL` (creating it and its schema if
    /// this is the first launch), attaches the catalogue at `catalogueURL`
    /// read-only as `cat`, and returns the one connection both live on.
    ///
    /// `today` drives the review-log replay migration, which needs the clock
    /// to decide how far to wind a historical batch forward; every other
    /// caller can leave it at the real one.
    ///
    /// Throws if the catalogue is missing or either database cannot be
    /// opened. There is no fallback: an in-memory review log would make the
    /// introduced-check lie about what has actually been shown.
    public static func open(catalogueURL: URL, reviewLogURL: URL, today: TodayProvider = TodayProvider()) throws -> DatabaseQueue {
        guard FileManager.default.fileExists(atPath: catalogueURL.path) else {
            throw LaoshuDatabaseError.catalogueNotFound(path: catalogueURL.path)
        }

        try FileManager.default.createDirectory(
            at: reviewLogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let dbQueue = try DatabaseQueue(path: reviewLogURL.path)

        // Attached before migrating, not after: the replay migration below
        // joins against `cat.word` for a word's level, so the catalogue has
        // to already be in scope by the time migrations run.
        try dbQueue.write { db in
            let escapedPath = catalogueURL.path.replacingOccurrences(of: "'", with: "''")
            try db.execute(sql: "ATTACH DATABASE 'file:\(escapedPath)?mode=ro' AS cat;")
        }

        try migrator(today: today).migrate(dbQueue)

        return dbQueue
    }

    /// The review log's schema, as an ordered list of versioned migrations
    /// GRDB applies in order and records in `grdb_migrations`, rather than
    /// bare `CREATE TABLE IF NOT EXISTS` statements that cannot tell a fresh
    /// database from one a later version needs to alter.
    private static func migrator(today: TodayProvider) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // `IF NOT EXISTS`, unlike every later migration, because a phone
        // upgrading from checkpoint 1 already has these two objects: that
        // version created them with bare `CREATE TABLE IF NOT EXISTS` and
        // recorded nothing, so there is no `grdb_migrations` row saying v1
        // is done and GRDB will run it. The definitions here are character
        // for character the ones checkpoint 1 shipped, so a database that
        // already has them is left exactly as a fresh one ends up.
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

        // Replaying the pre-batch review log runs as a migration on purpose.
        // `DatabaseMigrator` already wraps each migration in one transaction
        // and only records it as applied — in that same transaction — once
        // the block returns without throwing, which is exactly the "one
        // transaction, marker written with it, retried if interrupted, never
        // run twice" contract this migration needs.
        migrator.registerMigration("v3_replay_review_log_into_batches") { db in
            try ReviewLogReplay.run(db: db, today: today)
        }

        // D13/D13a: a single row recording whether the placement test has
        // been taken or declined, and the level it recommended (never set
        // when declined). A phone that already holds weeks of study — any
        // batch or review row — is seeded as already taken with no
        // recommended level, so the first-run gate this table backs never
        // fires for a user who has been studying for weeks (D14). An empty
        // database is seeded not taken, so the gate fires.
        migrator.registerMigration("v4_placement") { db in
            try db.execute(sql: """
                CREATE TABLE placement (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    status TEXT NOT NULL CHECK (status IN ('not_taken', 'taken', 'declined')),
                    recommended_level INTEGER,
                    -- A declined test recommended nothing, and a test that has
                    -- not been taken cannot have. Written as a constraint
                    -- rather than a comment because the writer lands in a
                    -- later task, and a rule the schema does not hold is one
                    -- a migration has to add back later.
                    CHECK (status = 'taken' OR recommended_level IS NULL)
                );
                """)

            let alreadyStudied = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM batch) OR EXISTS(SELECT 1 FROM review);
                """) ?? false

            try db.execute(
                sql: "INSERT INTO placement (id, status, recommended_level) VALUES (1, ?, NULL);",
                arguments: [alreadyStudied ? "taken" : "not_taken"]
            )
        }

        // D5: a single row recording which way a study session asks, shaped
        // like `placement` above. Lives in the database, not `UserDefaults`,
        // so a test can reach it (checkpoint 1 D10). One setting for the
        // whole app, seeded receptive.
        migrator.registerMigration("v5_preference") { db in
            try db.execute(sql: """
                CREATE TABLE preference (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    direction TEXT NOT NULL CHECK (direction IN ('receptive', 'reverse'))
                );
                """)
            try db.execute(sql: "INSERT INTO preference (id, direction) VALUES (1, 'receptive');")
        }

        // D9, D10, D11: the two settings the draw reads alongside direction,
        // added as columns on the same row rather than a second table —
        // there is still exactly one of each, seeded to the constants they
        // replace.
        migrator.registerMigration("v6_settings") { db in
            try db.execute(sql: """
                ALTER TABLE preference ADD COLUMN new_words_per_day INTEGER NOT NULL DEFAULT 8
                    CHECK (new_words_per_day BETWEEN 4 AND 20);
                """)
            try db.execute(sql: """
                ALTER TABLE preference ADD COLUMN speak_on_flip INTEGER NOT NULL DEFAULT 1
                    CHECK (speak_on_flip IN (0, 1));
                """)
        }

        // D26: the two tables a study session is kept in, so closing the app
        // mid-session no longer loses the queue. `session_one_live_per_level`
        // makes a second live session on the same level a failed write
        // rather than two queues racing (D5b's reasoning applied to the
        // session itself); `session_card_one_card_per_position` does the
        // same for two cards claiming the same place in one session's queue.
        migrator.registerMigration("v7_session") { db in
            try db.execute(sql: """
                CREATE TABLE session (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    level INTEGER NOT NULL,
                    created_on TEXT NOT NULL,
                    direction TEXT NOT NULL CHECK (direction IN ('receptive', 'reverse')),
                    speak_on_flip INTEGER NOT NULL CHECK (speak_on_flip IN (0, 1)),
                    new_words_batch_id INTEGER REFERENCES batch (id),
                    status TEXT NOT NULL CHECK (status IN ('live', 'done', 'abandoned'))
                );
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX session_one_live_per_level ON session (level) WHERE status = 'live';
                """)
            try db.execute(sql: """
                CREATE TABLE session_card (
                    session_id INTEGER NOT NULL REFERENCES session (id),
                    word_index INTEGER NOT NULL,
                    position INTEGER,
                    left_swipe_count INTEGER NOT NULL DEFAULT 0,
                    outcome TEXT CHECK (outcome IN ('finished', 'parked')),
                    settled_order INTEGER,
                    PRIMARY KEY (session_id, word_index)
                );
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX session_card_one_card_per_position
                    ON session_card (session_id, position) WHERE position IS NOT NULL;
                """)
        }

        // Route line 9: one row per level holding its most recent level
        // test result, replaced by the next attempt rather than kept as
        // history — the level list only ever needs to show the latest.
        // `level` is the primary key rather than an autoincrementing id
        // because there is exactly one row per level, the same shape as
        // `preference` and `placement` above being exactly one row.
        migrator.registerMigration("v8_level_test") { db in
            try db.execute(sql: """
                CREATE TABLE level_test (
                    level INTEGER PRIMARY KEY,
                    taken_on TEXT NOT NULL,
                    correct_count INTEGER NOT NULL,
                    total_count INTEGER NOT NULL,
                    passed INTEGER NOT NULL CHECK (passed IN (0, 1))
                );
                """)
        }

        // Route line 13: which installed voice speaks a card and how fast.
        // Both columns on the same `preference` row, the same shape D9-D11
        // used for the settings that came before them. `voice_identifier` is
        // nullable — no chosen voice means "let the app pick the best
        // Mandarin voice installed," not an error. `speech_rate` mirrors
        // `AVSpeechUtterance.rate`'s own 0.0-1.0 range, stored as a plain
        // `Double` here since `LaoshuKit` cannot import AVFoundation to
        // reference its constants directly.
        migrator.registerMigration("v9_voice_and_rate") { db in
            try db.execute(sql: "ALTER TABLE preference ADD COLUMN voice_identifier TEXT;")
            try db.execute(sql: """
                ALTER TABLE preference ADD COLUMN speech_rate REAL NOT NULL DEFAULT 0.5
                    CHECK (speech_rate BETWEEN 0.0 AND 1.0);
                """)
        }

        return migrator
    }

    /// The catalogue's location inside the app bundle. Only the app target
    /// has a meaningful bundle to ask; tests build their own catalogue files
    /// instead.
    public static func defaultCatalogueURL(bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(forResource: "laoshu", withExtension: "sqlite") else {
            throw LaoshuDatabaseError.catalogueNotFound(path: "\(bundle.bundleURL.path)/laoshu.sqlite")
        }
        return url
    }

    /// Where the writable review log lives: Application Support, so it
    /// survives app updates and is excluded from iCloud backup by default
    /// only if the caller marks it so.
    public static func defaultReviewLogURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("review.sqlite")
    }
}
