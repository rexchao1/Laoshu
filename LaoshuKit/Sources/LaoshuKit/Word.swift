import GRDB

/// A row of the bundled catalogue, as read back through `cat.word`.
public struct Word: Sendable, Equatable, FetchableRecord {
    public let wordIndex: Int
    public let level: Int
    public let hanzi: String
    public let pinyin: String
    public let pinyinNumbered: String
    public let definition: String

    public init(
        wordIndex: Int,
        level: Int,
        hanzi: String,
        pinyin: String,
        pinyinNumbered: String,
        definition: String
    ) {
        self.wordIndex = wordIndex
        self.level = level
        self.hanzi = hanzi
        self.pinyin = pinyin
        self.pinyinNumbered = pinyinNumbered
        self.definition = definition
    }

    public init(row: Row) {
        wordIndex = row["word_index"]
        level = row["level"]
        hanzi = row["hanzi"]
        pinyin = row["pinyin"]
        pinyinNumbered = row["pinyin_numbered"]
        definition = row["definition"]
    }

    /// Fetches every word in `indices` from `cat.word`, restored to
    /// `indices`'s own order — `IN` returns rows in whatever order SQLite
    /// likes, which would undo a caller's shuffle. Shared by a study
    /// session's draw and the placement test's block draw.
    static func fetch(indices: [Int], dbQueue: DatabaseQueue) throws -> [Word] {
        guard !indices.isEmpty else { return [] }
        let placeholders = databaseQuestionMarks(count: indices.count)
        let rows = try dbQueue.read { db in
            try Word.fetchAll(
                db,
                sql: """
                SELECT word_index, level, hanzi, pinyin, pinyin_numbered, definition
                FROM cat.word
                WHERE word_index IN (\(placeholders));
                """,
                arguments: StatementArguments(indices)
            )
        }
        let byIndex = Dictionary(uniqueKeysWithValues: rows.map { ($0.wordIndex, $0) })
        return indices.compactMap { byIndex[$0] }
    }
}
