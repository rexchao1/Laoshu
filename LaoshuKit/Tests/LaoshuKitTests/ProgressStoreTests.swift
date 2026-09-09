import Foundation
import Testing
import GRDB
@testable import LaoshuKit

/// Drives `TodayProvider` with a fixed clock instead of the system one
/// (mirrors `BatchTests.swift` and `SessionEngineTests.swift`).
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

private func progress(for level: Int, in all: [LevelProgress]) throws -> LevelProgress {
    try #require(all.first { $0.level == level })
}

/// A word the placement test marked known reads learned, not left (D10).
@Test func testWordInARetiredBatchReadsLearned() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))
    try BatchStore(dbQueue: dbQueue).createRetiredBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.learnedCount == 1)
    #expect(level1.inProgressCount == 0)
    #expect(level1.leftCount == 4)
    #expect(level1.waitingCount == 0)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// A word in a batch with a look still due reads in progress (D12).
@Test func testWordInABatchWithALookStillDueReadsInProgress() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))
    try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.learnedCount == 0)
    #expect(level1.inProgressCount == 1)
    #expect(level1.leftCount == 4)
    #expect(level1.waitingCount == 0)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// A word in no batch reads left (D12).
@Test func testWordInNoBatchReadsLeft() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.learnedCount == 0)
    #expect(level1.inProgressCount == 0)
    #expect(level1.leftCount == 5)
    #expect(level1.waitingCount == 0)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// A batch due today is counted once in waiting and is not added to the
/// level's other three numbers (D13, D14): it is already inside
/// `inProgressCount`, not on top of it.
@Test func testBatchDueTodayIsCountedOnceInWaitingAndNotAddedElsewhere() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))
    let day1 = provider(at: date(2026, 1, 2))
    try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: day1).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.waitingCount == 1)
    #expect(level1.inProgressCount == 1)
    #expect(level1.learnedCount == 0)
    #expect(level1.leftCount == 4)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// A batch due tomorrow reads in progress and not waiting (D13, D14).
@Test func testBatchDueTomorrowReadsInProgressAndNotWaiting() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))
    try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.inProgressCount == 1)
    #expect(level1.waitingCount == 0)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// A batch whose look is overdue reads waiting (D13).
@Test func testBatchWhoseLookIsOverdueReadsWaiting() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))
    let wellPast = provider(at: date(2026, 3, 1))
    try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: wellPast).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.waitingCount == 1)
    #expect(level1.inProgressCount == 1)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// The same word written into two batches, one retired and one due, reads
/// in progress rather than learned and is counted once (D16).
@Test func testWordInARetiredBatchAndADueBatchReadsInProgressOnce() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5, level: 1)
    let day0 = provider(at: date(2026, 1, 1))
    let store = BatchStore(dbQueue: dbQueue)
    try store.createRetiredBatch(level: 1, wordIndices: [1], today: day0)
    try store.createBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()
    let level1 = try progress(for: 1, in: all)

    #expect(level1.inProgressCount == 1)
    #expect(level1.learnedCount == 0)
    #expect(level1.leftCount == 4)
    #expect(level1.learnedCount + level1.inProgressCount + level1.leftCount == level1.wordCount)
}

/// A level with nothing studied reads 0 learned, 0 in progress and its full
/// word count left, independent of another level's own batches.
@Test func testLevelWithNothingStudiedReadsFullWordCountLeft() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 5, 2: 5])
    let day0 = provider(at: date(2026, 1, 1))
    try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1], today: day0)

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()
    let level2 = try progress(for: 2, in: all)

    #expect(level2.learnedCount == 0)
    #expect(level2.inProgressCount == 0)
    #expect(level2.leftCount == 5)
    #expect(level2.waitingCount == 0)
    #expect(level2.learnedCount + level2.inProgressCount + level2.leftCount == level2.wordCount)
}

/// Levels are returned in level order.
@Test func testProgressIsReturnedInLevelOrder() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 3, 2: 3, 3: 3])
    let day0 = provider(at: date(2026, 1, 1))

    let all = try ProgressStore(dbQueue: dbQueue, today: day0).progress()

    #expect(all.map(\.level) == [1, 2, 3])
}
