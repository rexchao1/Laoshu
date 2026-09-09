import Foundation
import GRDB
import Testing
@testable import LaoshuKit

/// Route line 9: a level test samples a level's words, grades each once with
/// no requeue, and writes a `level_test` row only on the final answer.
private func localDate(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

private func provider(at date: LocalDate) -> TodayProvider {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let instant = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))!
    return TodayProvider(calendar: calendar, clock: { instant })
}

@Test func testLevelTestSamplesEveryWordWhenTheLevelHasFewerThanTheCap() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let test = try engine.startLevelTest(level: 1)

    #expect(test.totalCount == 5)
}

@Test func testALeftAnswerIsAFinalWrongAnswerNotARequeue() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let test = try engine.startLevelTest(level: 1)
    var seen: [Int] = []
    while let card = test.currentCard {
        seen.append(card.word.wordIndex)
        try test.answer(.left)
    }

    // Every word appears exactly once — a wrong answer never comes back.
    #expect(seen.count == 3)
    #expect(Set(seen).count == 3)
    #expect(test.correctCount == 0)
    #expect(test.isFinished)
}

@Test func testResultIsWrittenOnlyOnceTheLastCardIsAnswered() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let store = LevelTestStore(dbQueue: dbQueue)

    let test = try engine.startLevelTest(level: 1)
    try test.answer(.right)
    #expect(test.result == nil)
    #expect(try store.result(level: 1) == nil)

    try test.answer(.right)
    #expect(test.result == nil)

    try test.answer(.left)
    #expect(test.result != nil)
    let stored = try #require(try store.result(level: 1))
    #expect(stored.correctCount == 2)
    #expect(stored.totalCount == 3)
}

@Test func testPassThresholdIsEightyPercent() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let passing = try engine.startLevelTest(level: 1)
    for direction: SwipeDirection in [.right, .right, .right, .right, .left] {
        try passing.answer(direction)
    }
    #expect(try #require(passing.result).passed == true)

    let failing = try engine.startLevelTest(level: 1)
    for direction: SwipeDirection in [.right, .right, .right, .left, .left] {
        try failing.answer(direction)
    }
    #expect(try #require(failing.result).passed == false)
}

@Test func testASecondAttemptOverwritesTheFirst() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let store = LevelTestStore(dbQueue: dbQueue)

    let first = try engine.startLevelTest(level: 1)
    for _ in 0..<3 { try first.answer(.left) }
    #expect(try store.result(level: 1)?.correctCount == 0)

    let second = try engine.startLevelTest(level: 1)
    for _ in 0..<3 { try second.answer(.right) }

    let rowCount = try dbQueue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM level_test") }
    #expect(rowCount == 1)
    #expect(try store.result(level: 1)?.correctCount == 3)
}

@Test func testLevelTestUsesTheCurrentStudyDirection() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    try PreferenceStore(dbQueue: dbQueue).setDirection(.reverse)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let test = try engine.startLevelTest(level: 1)

    #expect(test.currentCard?.promptFace == .meaning)
    #expect(test.currentCard?.answerFace == .chinese)
}

@Test func testNoResultBeforeAnyLevelTestIsTaken() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    #expect(try engine.levelTestResult(level: 1) == nil)
}

/// This fixture is built on the schema checkpoint 11 actually shipped, not
/// by calling `LaoshuDatabase`'s own migrator and inserting rows afterward
/// (the same convention `PreferenceTests` follows for its own migrations).
@Test func testMigrationAddsLevelTestToADatabaseBuiltTheWayCheckpoint11Shipped() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint11ReviewLog(
        at: reviewLogURL,
        batches: [(level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: localDate(2026, 1, 2), lookNumber: 0, wordIndices: [1, 2, 3])],
        reviewRows: [(wordIndex: 4, reviewedAt: Date(), grade: .good)],
        placementStatus: "taken",
        placementRecommendedLevel: nil,
        direction: "reverse"
    )

    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)

    #expect(try LevelTestStore(dbQueue: dbQueue).result(level: 1) == nil)
    let rowCount = try dbQueue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM level_test") }
    #expect(rowCount == 0)

    // The failure with the most to lose here is not a missing table but a
    // migration that adds one and drops weeks of study on the way.
    let counts = try dbQueue.read { db -> (Int, Int, Int) in
        let batch = try Int.fetchOne(db, sql: "SELECT count(*) FROM batch") ?? 0
        let batchWord = try Int.fetchOne(db, sql: "SELECT count(*) FROM batch_word") ?? 0
        let review = try Int.fetchOne(db, sql: "SELECT count(*) FROM review") ?? 0
        return (batch, batchWord, review)
    }
    #expect(counts == (1, 3, 1))
}
