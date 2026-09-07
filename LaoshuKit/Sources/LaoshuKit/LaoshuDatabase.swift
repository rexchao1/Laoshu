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
    /// Throws if the catalogue is missing or either database cannot be
    /// opened. There is no fallback: an in-memory review log would make the
    /// introduced-check lie about what has actually been shown.
    public static func open(catalogueURL: URL, reviewLogURL: URL) throws -> DatabaseQueue {
        guard FileManager.default.fileExists(atPath: catalogueURL.path) else {
            throw LaoshuDatabaseError.catalogueNotFound(path: catalogueURL.path)
        }

        try FileManager.default.createDirectory(
            at: reviewLogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

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

            let escapedPath = catalogueURL.path.replacingOccurrences(of: "'", with: "''")
            try db.execute(sql: "ATTACH DATABASE 'file:\(escapedPath)?mode=ro' AS cat;")
        }

        return dbQueue
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
