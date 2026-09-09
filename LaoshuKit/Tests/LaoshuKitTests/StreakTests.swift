import Foundation
import Testing
import GRDB
@testable import LaoshuKit

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

/// Writes review rows directly, bypassing `SessionEngine` and `Session` —
/// the streak only cares about `review` rows, not batches.
private func insertReview(_ dbQueue: DatabaseQueue, wordIndex: Int = 1, at instant: Date) throws {
    try dbQueue.write { db in
        try ReviewLog.record(db, wordIndex: wordIndex, grade: .good, at: instant)
    }
}

@Test func testEmptyLogReadsZeroAndNone() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    let reader = StreakReader(dbQueue: dbQueue, today: today)

    let streak = try reader.read()

    #expect(streak.days == 0)
    #expect(streak.state == .none)
}

@Test func testStudiedTodayOnlyReadsOneAndStudiedToday() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    try insertReview(dbQueue, at: date(2026, 3, 10))

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 1)
    #expect(streak.state == .studiedToday)
}

@Test func testRunOfConsecutiveDaysReadsItsLength() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    for day in 6...10 {
        try insertReview(dbQueue, at: date(2026, 3, day))
    }

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 5)
    #expect(streak.state == .studiedToday)
}

@Test func testRunWithOneForgivenGapReadsStudiedDayCountNotSpan() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    // Studied 6, 7, missed 8, studied 9, 10 — a one-day forgiven gap.
    for day in [6, 7, 9, 10] {
        try insertReview(dbQueue, at: date(2026, 3, day))
    }

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 4)
    #expect(streak.state == .studiedToday)
}

@Test func testHeadOneDayBackReadsAliveAndNotYetToday() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    try insertReview(dbQueue, at: date(2026, 3, 9))

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 1)
    #expect(streak.state == .notYetToday)
}

@Test func testHeadTwoDaysBackReadsAliveAndRestDayUsed() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    try insertReview(dbQueue, at: date(2026, 3, 8))

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 1)
    #expect(streak.state == .restDayUsed)
}

@Test func testHeadThreeDaysBackReadsZeroAndNone() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    try insertReview(dbQueue, at: date(2026, 3, 7))

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 0)
    #expect(streak.state == .none)
}

@Test func testTwoRowsInOneBusinessDayCountAsOneDay() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    try insertReview(dbQueue, wordIndex: 1, at: date(2026, 3, 10, hour: 8))
    try insertReview(dbQueue, wordIndex: 2, at: date(2026, 3, 10, hour: 20))

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 1)
    #expect(streak.state == .studiedToday)
}

@Test func testRowAtThreeAMCountsAsThePreviousBusinessDay() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 10))
    // 03:00 on the 10th is still the business day of the 9th (04:00 boundary).
    try insertReview(dbQueue, at: date(2026, 3, 10, hour: 3))

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 1)
    #expect(streak.state == .notYetToday)
}

@Test func testSecondMissedDaySixDaysAfterAForgivenOneEndsTheRun() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 20))
    // Studied 14...20 (missing 13, forgiven) and 8...12 (missing 7, only
    // six days after day 13's forgiven gap) — the second gap is rejected,
    // ending the run there.
    for day in [20, 19, 18, 17, 16, 15, 14, 12, 11, 10, 9, 8] {
        try insertReview(dbQueue, at: date(2026, 3, day))
    }

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 12)
    #expect(streak.state == .studiedToday)
}

@Test func testSecondMissedDaySevenDaysAfterAForgivenOneDoesNotEndTheRun() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let today = provider(at: date(2026, 3, 20))
    // Studied 14...20 (missing 13, forgiven) and 7...12 (missing 6, seven
    // days after day 13's forgiven gap) plus 3...5 (missing 6 forgiven too)
    // — both gaps are far enough apart to both forgive, so the run
    // continues through all of it.
    for day in [20, 19, 18, 17, 16, 15, 14, 12, 11, 10, 9, 8, 7, 5, 4, 3] {
        try insertReview(dbQueue, at: date(2026, 3, day))
    }

    let streak = try StreakReader(dbQueue: dbQueue, today: today).read()

    #expect(streak.days == 16)
    #expect(streak.state == .studiedToday)
}

@Test func testFreshSessionSwipeReadsOneAndStudiedToday() throws {
    let dbQueue = try TestFixtures.makeDatabase()
    let realToday = TodayProvider()
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: realToday)

    let session = try engine.startSession(level: 1)
    #expect(session.currentCard != nil)
    try session.swipe(.right)

    let streak = try StreakReader(dbQueue: dbQueue, today: realToday).read()

    #expect(streak.days == 1)
    #expect(streak.state == .studiedToday)
}
