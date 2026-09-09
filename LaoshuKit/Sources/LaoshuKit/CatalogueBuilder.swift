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
        public let gloss: String
    }

    /// A row as it appears in `data/glosses.tsv`.
    public struct GlossRow: Sendable {
        public let wordIndex: Int
        public let gloss: String
    }

    /// D5a: the maximum length, in characters, of a gloss.
    public static let maxGlossLength = 40

    public enum BuildError: Error, CustomStringConvertible, Equatable {
        case emptyDefinition(wordIndex: Int)
        case duplicateWordIndex(wordIndex: Int)
        case emptyGloss(wordIndex: Int)
        case glossTooLong(wordIndex: Int)
        case bannedGlossPattern(wordIndex: Int)
        case unknownGlossWordIndex(wordIndex: Int)
        case duplicateGlossWordIndex(wordIndex: Int)
        case missingGloss(wordIndex: Int)
        case malformedGlossLine(lineNumber: Int)

        public var description: String {
            switch self {
            case .emptyDefinition(let wordIndex):
                return "word_index \(wordIndex) cleaned to an empty definition"
            case .duplicateWordIndex(let wordIndex):
                return "word_index \(wordIndex) is not unique after collapsing"
            case .emptyGloss(let wordIndex):
                return "word_index \(wordIndex) has an empty gloss"
            case .glossTooLong(let wordIndex):
                return "word_index \(wordIndex)'s gloss is over \(maxGlossLength) characters"
            case .bannedGlossPattern(let wordIndex):
                return "word_index \(wordIndex)'s gloss carries a banned pattern"
            case .unknownGlossWordIndex(let wordIndex):
                return "word_index \(wordIndex) in the gloss file is not in the built word set"
            case .duplicateGlossWordIndex(let wordIndex):
                return "word_index \(wordIndex) appears more than once in the gloss file"
            case .missingGloss(let wordIndex):
                return "word_index \(wordIndex) has no gloss row"
            case .malformedGlossLine(let lineNumber):
                return "malformed gloss row at line \(lineNumber)"
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
    /// cleans definitions, and attaches each word's gloss from `glossLines`
    /// (the non-header lines of `data/glosses.tsv`). Throws naming the
    /// offending `word_index` if a definition cleans to empty, `word_index`
    /// is not unique after collapsing, or a gloss fails validation; throws
    /// naming the line number for a malformed gloss row.
    public static func buildCatalogue(from rows: [SourceRow], glossLines: [String]) throws -> [CleanWord] {
        let kept = rows.filter { keptLevels.contains($0.level) }
        let collapsed = collapse(kept)

        var seen = Set<Int>()
        for row in collapsed {
            guard seen.insert(row.wordIndex).inserted else {
                throw BuildError.duplicateWordIndex(wordIndex: row.wordIndex)
            }
        }

        let cleanedRows = try collapsed.map { row -> (SourceRow, String) in
            let definition = cleanDefinition(row.definition)
            guard !definition.isEmpty else {
                throw BuildError.emptyDefinition(wordIndex: row.wordIndex)
            }
            return (row, definition)
        }

        let glossMap = try buildGlossMap(
            fromLines: glossLines,
            wordIndices: Set(cleanedRows.map { $0.0.wordIndex })
        )

        return cleanedRows.map { row, definition in
            CleanWord(
                wordIndex: row.wordIndex,
                level: row.level,
                hanzi: stripSuffix(row.word),
                pinyin: row.pinyin,
                pinyinNumbered: row.pinyinNumbered,
                definition: definition,
                gloss: glossMap[row.wordIndex]!
            )
        }
    }

    /// Parses one non-header line of `data/glosses.tsv`. `nil` if the line is
    /// not exactly a `word_index` and a gloss separated by a tab.
    public static func parseGlossLine(_ line: String) -> GlossRow? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 2, let wordIndex = Int(fields[0]) else {
            return nil
        }
        return GlossRow(wordIndex: wordIndex, gloss: String(fields[1]))
    }

    /// D5a: throws naming `wordIndex` if `gloss` is empty, over
    /// `maxGlossLength` characters, or carries a banned pattern.
    public static func validateGloss(_ gloss: String, wordIndex: Int) throws {
        guard !gloss.isEmpty else {
            throw BuildError.emptyGloss(wordIndex: wordIndex)
        }
        guard gloss.count <= maxGlossLength else {
            throw BuildError.glossTooLong(wordIndex: wordIndex)
        }
        guard !containsBannedGlossPattern(gloss) else {
            throw BuildError.bannedGlossPattern(wordIndex: wordIndex)
        }
    }

    /// Parses and validates every line of `data/glosses.tsv` (minus its
    /// header) against `wordIndices` — the word set the catalogue actually
    /// built. Throws on a malformed line, a failed `validateGloss`, a
    /// `word_index` outside `wordIndices`, a `word_index` repeated in the
    /// file, or a member of `wordIndices` left without a gloss row.
    public static func buildGlossMap(fromLines lines: [String], wordIndices: Set<Int>) throws -> [Int: String] {
        var glosses: [Int: String] = [:]
        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 2 // header is line 1
            guard let row = parseGlossLine(line) else {
                throw BuildError.malformedGlossLine(lineNumber: lineNumber)
            }
            try validateGloss(row.gloss, wordIndex: row.wordIndex)
            guard wordIndices.contains(row.wordIndex) else {
                throw BuildError.unknownGlossWordIndex(wordIndex: row.wordIndex)
            }
            guard glosses[row.wordIndex] == nil else {
                throw BuildError.duplicateGlossWordIndex(wordIndex: row.wordIndex)
            }
            glosses[row.wordIndex] = row.gloss
        }
        for wordIndex in wordIndices.sorted() {
            guard glosses[wordIndex] != nil else {
                throw BuildError.missingGloss(wordIndex: wordIndex)
            }
        }
        return glosses
    }
}

/// D5a: a gloss may not carry hanzi, a bracketed pinyin reference, a
/// trailing `...`, `variant of` (which also catches `old variant of` and
/// `erhua variant of`), `abbr. for`, `(bound form)`, or "surname" followed
/// by a capitalised word (a bare "surname" is fine, as in "surname; family
/// name").
private func containsBannedGlossPattern(_ gloss: String) -> Bool {
    if gloss.hasSuffix("...") {
        return true
    }
    if matches(hanziRegex, gloss) || matches(bracketedPinyinRegex, gloss) || matches(surnameCapitalizedRegex, gloss) {
        return true
    }
    for phrase in ["variant of", "abbr. for", "(bound form)"] {
        if gloss.contains(phrase) {
            return true
        }
    }
    return false
}

private func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    return regex.firstMatch(in: string, options: [], range: range) != nil
}

private let clauseRegex = try! NSRegularExpression(
    pattern: #"/(CL:|variant of|see also|abbr\. for|old variant of)[^/]*"#
)
private let parentheticalRegex = try! NSRegularExpression(
    pattern: #"\([^()]*(?:[\x{4E00}-\x{9FFF}]|\[[a-z0-9 ]+\])[^()]*\)"#
)
private let whitespaceRegex = try! NSRegularExpression(pattern: #"\s{2,}"#)
private let hanziRegex = try! NSRegularExpression(pattern: #"[\x{4E00}-\x{9FFF}]"#)
private let bracketedPinyinRegex = try! NSRegularExpression(pattern: #"\[[a-z0-9 ]+\]"#)
private let surnameCapitalizedRegex = try! NSRegularExpression(pattern: #"surname [A-Z]"#)

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
