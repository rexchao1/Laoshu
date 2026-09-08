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

        let reviewLogURL = directory.appendingPathComponent("review.sqlite")
        return try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
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
