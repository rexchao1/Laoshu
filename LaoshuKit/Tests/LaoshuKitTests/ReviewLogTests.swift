import Foundation
import GRDB
import Testing
@testable import LaoshuKit

@Test func testSwipeRoundTrips() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let reviewLog = ReviewLog(dbQueue: dbQueue)

    try reviewLog.record(wordIndex: 3, grade: .again)
    try reviewLog.record(wordIndex: 3, grade: .good)

    let rows = try dbQueue.read { db in
        try Row.fetchAll(db, sql: "SELECT word_index, grade FROM review ORDER BY reviewed_at;")
    }

    #expect(rows.count == 2)
    #expect(rows[0]["word_index"] as Int == 3)
    #expect(rows[0]["grade"] as String == Grade.again.rawValue)
    #expect(rows[1]["word_index"] as Int == 3)
    #expect(rows[1]["grade"] as String == Grade.good.rawValue)
}

@Test func testIntroducedTestSeesLoggedWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let reviewLog = ReviewLog(dbQueue: dbQueue)

    #expect(try reviewLog.isIntroduced(wordIndex: 5) == false)

    try reviewLog.record(wordIndex: 5, grade: .again)

    #expect(try reviewLog.isIntroduced(wordIndex: 5) == true)
    #expect(try reviewLog.isIntroduced(wordIndex: 6) == false)
}
