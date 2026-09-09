import Foundation
import GRDB
import Testing
@testable import LaoshuKit

/// Exercises the review-log replay migration through the real upgrade path:
/// a review log already on the pre-batch schema, opened for the first time
/// after the code that adds batches, same as `LaoshuDatabase`'s own tests
/// for the ladder itself (a fixed-clock seam).
private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func provider(at instant: Date) -> TodayProvider {
    TodayProvider(calendar: testCalendar, clock: { instant })
}

private func localDate(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

private struct BatchRow {
    let level: Int
    let createdOn: LocalDate
    let nextLookOn: LocalDate?
    let lookNumber: Int
    let wordIndices: [Int]
}

private func fetchBatches(_ dbQueue: DatabaseQueue) throws -> [BatchRow] {
    try dbQueue.read { db in
        let rows = try Row.fetchAll(db, sql: "SELECT id, level, created_on, next_look_on, look_number FROM batch;")
        return try rows.map { row in
            let id: Int64 = row["id"]
            let wordIndices = try Int.fetchAll(
                db,
                sql: "SELECT word_index FROM batch_word WHERE batch_id = ? ORDER BY word_index;",
                arguments: [id]
            )
            return BatchRow(
                level: row["level"],
                createdOn: row["created_on"],
                nextLookOn: row["next_look_on"],
                lookNumber: row["look_number"],
                wordIndices: wordIndices
            )
        }
    }
}

@Test func testReplayGroupsByDayAndLevelAndWindsEachBatchForward() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 10, 2: 10])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    let dayOne = date(2026, 1, 1)
    let dayFour = date(2026, 1, 4)
    try TestFixtures.makePreUpgradeReviewLog(
        at: reviewLogURL,
        rows: [
            (wordIndex: 1, reviewedAt: dayOne, grade: .again),
            (wordIndex: 2, reviewedAt: dayOne, grade: .good), // groups with word 1: same day, same level
            (wordIndex: 11, reviewedAt: dayOne, grade: .good), // same day, level 2: a separate batch
            (wordIndex: 3, reviewedAt: dayFour, grade: .good), // same level as 1/2, different day: a separate batch
        ]
    )

    // 1/2 and 1/9 (first and second look for the 1/1 group) have both
    // passed; 1/9 is not yet more than seven days behind, so nothing
    // retires. The 1/4 group's first look (1/5) has passed too, but its
    // second look (1/12) is still in the future.
    let today = provider(at: date(2026, 1, 8))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)

    let batches = try fetchBatches(dbQueue)
    #expect(batches.count == 3)

    let dayOneLevelOne = try #require(batches.first { $0.createdOn == localDate(2026, 1, 1) && $0.level == 1 })
    #expect(dayOneLevelOne.wordIndices == [1, 2])
    #expect(dayOneLevelOne.lookNumber == 1)
    #expect(dayOneLevelOne.nextLookOn == localDate(2026, 1, 9))

    let dayOneLevelTwo = try #require(batches.first { $0.createdOn == localDate(2026, 1, 1) && $0.level == 2 })
    #expect(dayOneLevelTwo.wordIndices == [11])
    #expect(dayOneLevelTwo.lookNumber == 1)
    #expect(dayOneLevelTwo.nextLookOn == localDate(2026, 1, 9))

    let dayFourLevelOne = try #require(batches.first { $0.createdOn == localDate(2026, 1, 4) && $0.level == 1 })
    #expect(dayFourLevelOne.wordIndices == [3])
    #expect(dayFourLevelOne.lookNumber == 1)
    #expect(dayFourLevelOne.nextLookOn == localDate(2026, 1, 12))
}

/// The strict boundary at the migration level: a group whose first review
/// lands today has a first look due today, which has not been taken yet.
/// A previous attempt at this got this wrong by treating a look due today
/// as already taken, which would have advanced it to look number 1 and
/// pushed it out to the second rung a week early.
@Test func testReplayLeavesABatchDueTodayAtLookZero() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 5])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    // First review today; first look is due tomorrow under the normal
    // schedule, but the day boundary below lands `today` exactly on that
    // due date instead.
    try TestFixtures.makePreUpgradeReviewLog(
        at: reviewLogURL,
        rows: [(wordIndex: 1, reviewedAt: date(2026, 1, 1), grade: .good)]
    )

    let today = provider(at: date(2026, 1, 2))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)

    let batches = try fetchBatches(dbQueue)
    #expect(batches.count == 1)
    #expect(batches[0].lookNumber == 0)
    #expect(batches[0].nextLookOn == localDate(2026, 1, 2))
    #expect(batches[0].createdOn == localDate(2026, 1, 1))
}

@Test func testReplayRetiresABatchWhoseSecondLookIsMoreThanSevenDaysBehind() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 5])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makePreUpgradeReviewLog(
        at: reviewLogURL,
        rows: [(wordIndex: 1, reviewedAt: date(2026, 1, 1), grade: .good)]
    )

    // First look due 1/2, second look due 1/9; 1/17 is eight days behind.
    let today = provider(at: date(2026, 1, 17))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)

    let batches = try fetchBatches(dbQueue)
    #expect(batches.count == 1)
    #expect(batches[0].nextLookOn == nil)
}

@Test func testReplayNeverRunsTwice() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 5])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makePreUpgradeReviewLog(
        at: reviewLogURL,
        rows: [(wordIndex: 1, reviewedAt: date(2026, 1, 1), grade: .good)]
    )

    let today = provider(at: date(2026, 1, 8))

    func openAndFetchBatches() throws -> [BatchRow] {
        let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)
        return try fetchBatches(dbQueue)
    }

    let afterFirstLaunch = try openAndFetchBatches()
    #expect(afterFirstLaunch.count == 1)

    // A later launch — even one that could regroup the same review row —
    // must find the migration already recorded and leave the batch alone.
    let afterSecondLaunch = try openAndFetchBatches()
    #expect(afterSecondLaunch.count == 1)
    #expect(afterSecondLaunch[0].wordIndices == afterFirstLaunch[0].wordIndices)
    #expect(afterSecondLaunch[0].nextLookOn == afterFirstLaunch[0].nextLookOn)
}

@Test func testMigratedWordIsNeverDrawnAsNewAgain() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makePreUpgradeReviewLog(
        at: reviewLogURL,
        rows: [
            (wordIndex: 1, reviewedAt: date(2026, 1, 1), grade: .again),
            (wordIndex: 2, reviewedAt: date(2026, 1, 1), grade: .good),
        ]
    )

    // Chosen before the migrated batch's second look (1/9), so it stays due
    // rather than being pulled into this session as review, isolating the
    // "never drawn as new" question from the separate due-batch behavior.
    let today = provider(at: date(2026, 1, 8))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)
    let session = try engine.startSession(level: 1)

    // 8 words in the level, 2 already reviewed: only 6 are left to draw.
    #expect(session.drawnCount == 6)
    var seen: [Int] = []
    while let card = session.currentCard {
        seen.append(card.word.wordIndex)
        try session.swipe(.right)
    }
    #expect(!seen.contains(1))
    #expect(!seen.contains(2))
}
