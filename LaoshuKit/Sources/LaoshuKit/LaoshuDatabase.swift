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
    /// `today` drives the D18 replay migration, which needs the clock to
    /// decide how far to wind a historical batch forward; every other caller
    /// can leave it at the real one.
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

        migrator.registerMigration("v1_review_log") { db in
            try db.execute(sql: """
                CREATE TABLE review (
                    word_index INTEGER NOT NULL,
                    reviewed_at REAL NOT NULL,
                    grade TEXT NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX review_word_index ON review(word_index);")
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

        // D18: replaying the pre-batch review log runs as a migration on
        // purpose. `DatabaseMigrator` already wraps each migration in one
        // transaction and only records it as applied — in that same
        // transaction — once the block returns without throwing, which is
        // exactly the "one transaction, marker written with it, retried if
        // interrupted, never run twice" contract this migration needs.
        migrator.registerMigration("v3_replay_review_log_into_batches") { db in
            try ReviewLogReplay.run(db: db, today: today)
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
