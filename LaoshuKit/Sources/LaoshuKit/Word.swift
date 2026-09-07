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
}
