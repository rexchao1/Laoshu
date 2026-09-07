import Foundation
import SQLite3
import CryptoKit
import LaoshuKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    fail("""
    usage:
      laoshu-build-db <source.tsv> <database.sqlite>
      laoshu-build-db --checksum <database.sqlite>
    """)
}

// MARK: - TSV parsing

/// The columns `data/hsk_word_list.tsv` ships, in file order.
private enum Column: Int {
    case wordIndex = 0
    case level = 1
    case word = 2
    case pinyin = 3
    case partOfSpeech = 4
    case pinyinNumbered = 5
    case pinyinCedict = 6
    case traditionalCedict = 7
    case definitionCedict = 8
}

func readSourceRows(path: String) throws -> [CatalogueBuilder.SourceRow] {
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    var lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
    guard !lines.isEmpty else { return [] }
    lines.removeFirst() // header

    var rows: [CatalogueBuilder.SourceRow] = []
    rows.reserveCapacity(lines.count)
    for line in lines {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 9 else {
            fail("malformed source row, expected 9 fields, found \(fields.count): \(line)")
        }
        guard let wordIndex = Int(fields[Column.wordIndex.rawValue]) else {
            fail("malformed word_index: \(fields[Column.wordIndex.rawValue])")
        }
        // Rows outside HSK levels 1-6 (the source's "7-9" bucket) are not
        // numeric here; CatalogueBuilder filters by keptLevels, so give
        // those rows a sentinel level rather than failing the whole build.
        let level = Int(fields[Column.level.rawValue]) ?? Int.min
        rows.append(
            CatalogueBuilder.SourceRow(
                wordIndex: wordIndex,
                level: level,
                word: fields[Column.word.rawValue],
                pinyin: fields[Column.pinyin.rawValue],
                pinyinNumbered: fields[Column.pinyinNumbered.rawValue],
                definition: fields[Column.definitionCedict.rawValue]
            )
        )
    }
    return rows
}

// MARK: - SQLite

func sqliteCheck(_ code: Int32, _ db: OpaquePointer?, _ context: String) {
    guard code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW else {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        fail("\(context): \(message)")
    }
}

func writeDatabase(words: [CatalogueBuilder.CleanWord], to path: String) throws {
    var db: OpaquePointer?
    sqliteCheck(sqlite3_open(path, &db), db, "opening \(path)")
    defer { sqlite3_close(db) }

    sqliteCheck(sqlite3_exec(db, """
        CREATE TABLE word (
            word_index INTEGER PRIMARY KEY,
            level INTEGER NOT NULL,
            hanzi TEXT NOT NULL,
            pinyin TEXT NOT NULL,
            pinyin_numbered TEXT NOT NULL,
            definition TEXT NOT NULL
        );
        """, nil, nil, nil), db, "creating table")

    sqliteCheck(sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil), db, "beginning transaction")

    var statement: OpaquePointer?
    sqliteCheck(sqlite3_prepare_v2(db, """
        INSERT INTO word (word_index, level, hanzi, pinyin, pinyin_numbered, definition)
        VALUES (?, ?, ?, ?, ?, ?);
        """, -1, &statement, nil), db, "preparing insert")
    defer { sqlite3_finalize(statement) }

    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT
    for word in words {
        sqlite3_bind_int64(statement, 1, Int64(word.wordIndex))
        sqlite3_bind_int64(statement, 2, Int64(word.level))
        sqlite3_bind_text(statement, 3, word.hanzi, -1, transient)
        sqlite3_bind_text(statement, 4, word.pinyin, -1, transient)
        sqlite3_bind_text(statement, 5, word.pinyinNumbered, -1, transient)
        sqlite3_bind_text(statement, 6, word.definition, -1, transient)
        sqliteCheck(sqlite3_step(statement), db, "inserting word_index \(word.wordIndex)")
        sqlite3_reset(statement)
    }

    sqliteCheck(sqlite3_exec(db, "COMMIT;", nil, nil, nil), db, "committing transaction")
}

func readChecksumRows(from path: String) throws -> [String] {
    var db: OpaquePointer?
    sqliteCheck(sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil), db, "opening \(path)")
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    sqliteCheck(sqlite3_prepare_v2(db, """
        SELECT word_index, level, hanzi, pinyin, pinyin_numbered, definition
        FROM word ORDER BY word_index;
        """, -1, &statement, nil), db, "preparing checksum query")
    defer { sqlite3_finalize(statement) }

    var rows: [String] = []
    while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { break }
        sqliteCheck(step, db, "reading rows for checksum")
        let wordIndex = sqlite3_column_int64(statement, 0)
        let level = sqlite3_column_int64(statement, 1)
        let hanzi = String(cString: sqlite3_column_text(statement, 2))
        let pinyin = String(cString: sqlite3_column_text(statement, 3))
        let pinyinNumbered = String(cString: sqlite3_column_text(statement, 4))
        let definition = String(cString: sqlite3_column_text(statement, 5))
        rows.append("\(wordIndex)\t\(level)\t\(hanzi)\t\(pinyin)\t\(pinyinNumbered)\t\(definition)")
    }
    return rows
}

/// D14: a SHA-256 over the logical rows in `word_index` order, not the file's
/// bytes — SQLite's page layout differs between library versions.
func checksum(of rows: [String]) -> String {
    let joined = rows.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Atomic write (D13)

func atomicallyReplace(target: String, withContentsOf tempPath: String) throws {
    if rename(tempPath, target) != 0 {
        let errorMessage = String(cString: strerror(errno))
        try? FileManager.default.removeItem(atPath: tempPath)
        fail("could not replace \(target): \(errorMessage)")
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.count {
case 2 where arguments[0] == "--checksum":
    let rows = try readChecksumRows(from: arguments[1])
    print(checksum(of: rows))

case 2:
    let sourcePath = arguments[0]
    let outputPath = arguments[1]

    let sourceRows = try readSourceRows(path: sourcePath)
    let words: [CatalogueBuilder.CleanWord]
    do {
        words = try CatalogueBuilder.buildCatalogue(from: sourceRows)
    } catch {
        fail("\(error)")
    }

    let directory = (outputPath as NSString).deletingLastPathComponent
    let tempPath = (directory.isEmpty ? "." : directory) + "/.laoshu-build-db-\(UUID().uuidString).tmp"
    try? FileManager.default.removeItem(atPath: tempPath)

    try writeDatabase(words: words, to: tempPath)
    try atomicallyReplace(target: outputPath, withContentsOf: tempPath)

default:
    usage()
}
