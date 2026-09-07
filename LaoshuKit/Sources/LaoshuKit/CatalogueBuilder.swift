import Foundation

/// Turns raw HSK word list rows into the rows the shipped database holds.
///
/// The cleanup rules mirror `docs/measure.py`'s `clean()`, `strip_suffix()`
/// and `collapse()` exactly (checkpoint 1 PRD, decisions D8, D9, D15). The
/// counts asserted in `docs/measurements.md` are only true of this file's
/// output if it keeps matching that script.
public enum CatalogueBuilder {
    /// A row as it appears in `data/hsk_word_list.tsv`, restricted to the
    /// fields the catalogue needs.
    public struct SourceRow: Sendable {
        public let wordIndex: Int
        public let level: Int
        public let word: String
        public let pinyin: String
        public let pinyinNumbered: String
        public let definition: String

        public init(
            wordIndex: Int,
            level: Int,
            word: String,
            pinyin: String,
            pinyinNumbered: String,
            definition: String
        ) {
            self.wordIndex = wordIndex
            self.level = level
            self.word = word
            self.pinyin = pinyin
            self.pinyinNumbered = pinyinNumbered
            self.definition = definition
        }
    }

    /// A row ready to be written to the `word` table.
    public struct CleanWord: Sendable {
        public let wordIndex: Int
        public let level: Int
        public let hanzi: String
        public let pinyin: String
        public let pinyinNumbered: String
        public let definition: String
    }

    public enum BuildError: Error, CustomStringConvertible, Equatable {
        case emptyDefinition(wordIndex: Int)
        case duplicateWordIndex(wordIndex: Int)

        public var description: String {
            switch self {
            case .emptyDefinition(let wordIndex):
                return "word_index \(wordIndex) cleaned to an empty definition"
            case .duplicateWordIndex(let wordIndex):
                return "word_index \(wordIndex) is not unique after collapsing"
            }
        }
    }

    /// D2: only HSK levels 1 through 6 ship. The source's `7-9` bucket is discarded.
    public static let keptLevels: ClosedRange<Int> = 1...6

    /// D9: drop a trailing source-side disambiguation digit, e.g. `打1` -> `打`.
    public static func stripSuffix(_ word: String) -> String {
        var s = Substring(word)
        while let last = s.last, last.isASCII, last.isNumber {
            s.removeLast()
        }
        return String(s)
    }

    /// D8: the definition cleanup rule.
    public static func cleanDefinition(_ definition: String) -> String {
        var d = replaceAll(clauseRegex, in: definition, with: "")
        d = replaceAll(parentheticalRegex, in: d, with: "")
        d = replaceAll(whitespaceRegex, in: d, with: " ")

        let senses = d.split(separator: "/", omittingEmptySubsequences: false)
            .map { trimSensePunctuation(String($0)) }
            .filter { !$0.isEmpty }

        var out = senses.prefix(2).joined(separator: "; ")
        if out.count > 60 {
            out = senses.first ?? ""
        }
        if out.count > 90 {
            let prefix = String(out.prefix(87))
            if let lastSpace = prefix.range(of: " ", options: .backwards) {
                out = String(prefix[..<lastSpace.lowerBound]) + "..."
            } else {
                out = prefix + "..."
            }
        }
        return trimSensePunctuation(out)
    }

    /// D15: one row per `word_index`, kept at that word's lowest level.
    public static func collapse(_ rows: [SourceRow]) -> [SourceRow] {
        var best: [Int: SourceRow] = [:]
        for row in rows {
            if let existing = best[row.wordIndex] {
                if row.level < existing.level {
                    best[row.wordIndex] = row
                }
            } else {
                best[row.wordIndex] = row
            }
        }
        return best.values.sorted { $0.wordIndex < $1.wordIndex }
    }

    /// Filters to the kept levels, collapses duplicates, strips word suffixes,
    /// and cleans definitions. Throws naming the offending `word_index` if a
    /// definition cleans to empty or `word_index` is not unique after collapsing.
    public static func buildCatalogue(from rows: [SourceRow]) throws -> [CleanWord] {
        let kept = rows.filter { keptLevels.contains($0.level) }
        let collapsed = collapse(kept)

        var seen = Set<Int>()
        for row in collapsed {
            guard seen.insert(row.wordIndex).inserted else {
                throw BuildError.duplicateWordIndex(wordIndex: row.wordIndex)
            }
        }

        return try collapsed.map { row in
            let definition = cleanDefinition(row.definition)
            guard !definition.isEmpty else {
                throw BuildError.emptyDefinition(wordIndex: row.wordIndex)
            }
            return CleanWord(
                wordIndex: row.wordIndex,
                level: row.level,
                hanzi: stripSuffix(row.word),
                pinyin: row.pinyin,
                pinyinNumbered: row.pinyinNumbered,
                definition: definition
            )
        }
    }
}

private let clauseRegex = try! NSRegularExpression(
    pattern: #"/(CL:|variant of|see also|abbr\. for|old variant of)[^/]*"#
)
private let parentheticalRegex = try! NSRegularExpression(
    pattern: #"\([^()]*(?:[\x{4E00}-\x{9FFF}]|\[[a-z0-9 ]+\])[^()]*\)"#
)
private let whitespaceRegex = try! NSRegularExpression(pattern: #"\s{2,}"#)

private func replaceAll(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
}

private func trimSensePunctuation(_ s: String) -> String {
    let charsToTrim: Set<Character> = [" ", ";", ","]
    var result = Substring(s)
    while let first = result.first, charsToTrim.contains(first) {
        result.removeFirst()
    }
    while let last = result.last, charsToTrim.contains(last) {
        result.removeLast()
    }
    return String(result)
}
