import Foundation
import Testing
@testable import LaoshuKit

/// Drives `TodayProvider` with a fixed clock instead of waiting on the
/// system one, so an eight-day ladder is testable in a single run (D21).
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

@Test func testBatchIsNotUpTheDayItIsCreatedAndIsUpTheNextDay() throws {
    let day0 = localDate(2026, 1, 1)
    let day1 = localDate(2026, 1, 2)

    let batch = BatchScheduler.createBatch(level: 1, today: provider(at: date(2026, 1, 1)))

    #expect(batch.createdOn == day0)
    #expect(batch.nextLookOn == day1)
    #expect(batch.isDue(on: day0) == false)
    #expect(batch.isDue(on: day1) == true)
}

@Test func testBatchIsNotDueOnADayAfterItsLookWasMissed() throws {
    let batch = BatchScheduler.createBatch(level: 1, today: provider(at: date(2026, 1, 1)))

    #expect(batch.isDue(on: localDate(2026, 1, 2)) == true)
    #expect(batch.isDue(on: localDate(2026, 1, 3)) == false)
    #expect(batch.isDue(on: localDate(2026, 1, 10)) == false)
}

@Test func testBatchIsNotUpAgainUntilDayEightAfterAnOnTimeFirstLook() throws {
    let day1 = localDate(2026, 1, 2)
    let batch = BatchScheduler.createBatch(level: 1, today: provider(at: date(2026, 1, 1)))

    let afterFirstLook = batch.lookTaken(on: day1)

    #expect(afterFirstLook.nextLookOn == localDate(2026, 1, 9)) // day 8

    for offset in 2...7 {
        let notYetDue = localDate(2026, 1, 1).addingDays(offset)
        #expect(afterFirstLook.isDue(on: notYetDue) == false, "should not be due on day \(offset)")
    }
    #expect(afterFirstLook.isDue(on: localDate(2026, 1, 9)) == true)
}

@Test func testSecondLookIsAnchoredToWhenTheFirstLookWasActuallyTaken() throws {
    let batch = BatchScheduler.createBatch(level: 1, today: provider(at: date(2026, 1, 1)))

    // The day-1 look isn't taken until day 4, not on the day it was due.
    let lookTakenOnDay4 = localDate(2026, 1, 1).addingDays(4)
    let afterFirstLook = batch.lookTaken(on: lookTakenOnDay4)

    // Anchored to day 4, so day 4 + 7 = day 11, not day 0's day 8.
    #expect(afterFirstLook.nextLookOn == localDate(2026, 1, 1).addingDays(11))
    #expect(afterFirstLook.nextLookOn != localDate(2026, 1, 1).addingDays(8))
}

@Test func testEarlyMorningSessionFloorsTheFirstLookToTheDayAfterTheWallClockDay() throws {
    // A session at 01:00 on calendar day 2. The 04:00 boundary (D9) makes
    // this business day 1, but D4a floors the first look against the raw
    // wall-clock day (day 2) instead, so it lands on day 3.
    let earlyMorningOnDay2 = date(2026, 1, 2, hour: 1)
    let batch = BatchScheduler.createBatch(level: 1, today: provider(at: earlyMorningOnDay2))

    #expect(batch.nextLookOn == localDate(2026, 1, 3))

    // Not up later that same calendar day...
    let sameDayAt9am = date(2026, 1, 2, hour: 9)
    #expect(batch.isDue(on: provider(at: sameDayAt9am).today()) == false)

    // ...but up the next calendar day.
    let nextDayNoon = date(2026, 1, 3, hour: 12)
    #expect(batch.isDue(on: provider(at: nextDayNoon).today()) == true)
}

@Test func testBatchRetiresAfterItsSecondLookAndNeverComesUpAgain() throws {
    let batch = BatchScheduler.createBatch(level: 1, today: provider(at: date(2026, 1, 1)))
    let day1 = localDate(2026, 1, 2)

    let afterFirstLook = batch.lookTaken(on: day1)
    #expect(afterFirstLook.isRetired == false)

    let afterSecondLook = afterFirstLook.lookTaken(on: afterFirstLook.nextLookOn!)
    #expect(afterSecondLook.isRetired == true)
    #expect(afterSecondLook.nextLookOn == nil)

    for offset in 0...30 {
        let future = localDate(2026, 1, 1).addingDays(offset)
        #expect(afterSecondLook.isDue(on: future) == false, "a retired batch must never come up again")
    }
}

@Test func testReplayBatchAutoCompletesAnOverdueFirstLookAndLeavesTheSecondDue() throws {
    let createdOn = localDate(2026, 1, 1)
    let today = localDate(2026, 1, 10) // first look (1/2) and second look (1/9) both passed; gap on the second is 1 day.

    let batch = BatchScheduler.replayBatch(level: 1, createdOn: createdOn, today: today)

    #expect(batch.lookNumber == 1)
    #expect(batch.nextLookOn == localDate(2026, 1, 9))
    #expect(batch.isRetired == false)
}

@Test func testReplayBatchLeavesAFutureFirstLookAlone() throws {
    let createdOn = localDate(2026, 1, 1)
    let today = localDate(2026, 1, 1) // before the first look is even due.

    let batch = BatchScheduler.replayBatch(level: 1, createdOn: createdOn, today: today)

    #expect(batch.lookNumber == 0)
    #expect(batch.nextLookOn == localDate(2026, 1, 2))
    #expect(batch.isRetired == false)
}

/// The strict boundary: a look due today has not been taken yet, so replay
/// must leave it alone rather than treat it as already taken.
@Test func testReplayBatchLeavesAFirstLookDueTodayUntaken() throws {
    let createdOn = localDate(2026, 1, 1)
    let today = localDate(2026, 1, 2) // exactly the first look's due date.

    let batch = BatchScheduler.replayBatch(level: 1, createdOn: createdOn, today: today)

    #expect(batch.lookNumber == 0)
    #expect(batch.nextLookOn == localDate(2026, 1, 2))
    #expect(batch.isRetired == false)
    #expect(batch.isDue(on: today) == true)
}

@Test func testReplayBatchWindsForwardOnceTheFirstLookIsStrictlyInThePast() throws {
    let createdOn = localDate(2026, 1, 1)
    let today = localDate(2026, 1, 3) // the day after the first look's due date.

    let batch = BatchScheduler.replayBatch(level: 1, createdOn: createdOn, today: today)

    #expect(batch.lookNumber == 1)
    #expect(batch.nextLookOn == localDate(2026, 1, 9))
}

@Test func testReplayBatchRetiresASecondLookMoreThanSevenDaysBehind() throws {
    let createdOn = localDate(2026, 1, 1)
    // First look due 1/2, second look due 1/9. Eight days behind on the
    // second look is one more than the seven-day grace.
    let today = localDate(2026, 1, 17)

    let batch = BatchScheduler.replayBatch(level: 1, createdOn: createdOn, today: today)

    #expect(batch.isRetired == true)
    #expect(batch.lookNumber == 2) // retired batches carry look number 2, whether the
    // second look was taken or given up on, so the row shape matches the one
    // normal operation writes.
}

@Test func testReplayBatchDoesNotRetireASecondLookExactlySevenDaysBehind() throws {
    let createdOn = localDate(2026, 1, 1)
    // Second look due 1/9; exactly seven days behind is still within grace.
    let today = localDate(2026, 1, 16)

    let batch = BatchScheduler.replayBatch(level: 1, createdOn: createdOn, today: today)

    #expect(batch.isRetired == false)
    #expect(batch.nextLookOn == localDate(2026, 1, 9))
}

@Test func testBatchStoreCreatesAndAdvancesAPersistedBatch() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)

    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    #expect(created.nextLookOn == localDate(2026, 1, 2))
    #expect(try store.dueBatches(today: day0).isEmpty)

    let day1 = provider(at: date(2026, 1, 2))
    #expect(try store.dueBatches(today: day1).map(\.id) == [batchID])

    let afterFirstLook = try store.recordLook(batchID: batchID, today: day1)
    #expect(afterFirstLook.lookNumber == 1)
    #expect(afterFirstLook.nextLookOn == localDate(2026, 1, 9))
    #expect(try store.dueBatches(today: day1).isEmpty)

    let day8 = provider(at: date(2026, 1, 9))
    let afterSecondLook = try store.recordLook(batchID: batchID, today: day8)
    #expect(afterSecondLook.lookNumber == 2)
    #expect(afterSecondLook.isRetired == true)
    #expect(try store.dueBatches(today: day8).isEmpty)

    let fetched = try #require(try store.fetchBatch(id: batchID))
    #expect(fetched.isRetired == true)
}

/// D14: introduced is decided by batch membership, not by a review row —
/// this is what fixes the word a session parks by three left swipes never
/// coming back as new.
@Test func testIsIntroducedReflectsBatchMembershipNotReviewRows() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)

    #expect(try store.isIntroduced(wordIndex: 5) == false)

    try store.createBatch(level: 1, wordIndices: [5], today: provider(at: date(2026, 1, 1)))

    #expect(try store.isIntroduced(wordIndex: 5) == true)
    #expect(try store.isIntroduced(wordIndex: 6) == false)
}

@Test func testHasBatchCreatedTodayIsPerDayAcrossLevels() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 8, 2: 8])
    let store = BatchStore(dbQueue: dbQueue)

    let day0 = provider(at: date(2026, 1, 1))
    #expect(try store.hasBatchCreatedToday(today: day0) == false)

    try store.createBatch(level: 2, wordIndices: [9], today: day0)

    #expect(try store.hasBatchCreatedToday(today: day0) == true)

    let day1 = provider(at: date(2026, 1, 2))
    #expect(try store.hasBatchCreatedToday(today: day1) == false)
}

/// D6: a batch's own ladder can never retire it the day it is created —
/// `BatchScheduler.createBatch` always sets `next_look_on`, and
/// `Batch.lookTaken` only nulls it on the second look, at least eight days
/// later. So a retired batch dated today can only exist some other way
/// (e.g. a batch a user retired outright); this writes one directly to
/// prove the allowance query ignores it rather than exercising the normal
/// ladder, which cannot produce this shape.
@Test func testHasBatchCreatedTodayIgnoresARetiredBatch() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)

    let day0 = provider(at: date(2026, 1, 1))
    try dbQueue.write { db in
        try db.execute(
            sql: """
            INSERT INTO batch (level, created_on, next_look_on, look_number)
            VALUES (1, ?, NULL, 2);
            """,
            arguments: [localDate(2026, 1, 1)]
        )
    }

    #expect(try store.hasBatchCreatedToday(today: day0) == false)
}

@Test func testHasActiveBatchIsTrueUntilTheBatchRetires() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)

    #expect(try store.hasActiveBatch(level: 1) == false)

    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1], today: day0)
    let batchID = try #require(created.id)

    #expect(try store.hasActiveBatch(level: 1) == true)

    let day1 = provider(at: date(2026, 1, 2))
    try store.recordLook(batchID: batchID, today: day1)
    #expect(try store.hasActiveBatch(level: 1) == true)

    let day8 = provider(at: date(2026, 1, 9))
    try store.recordLook(batchID: batchID, today: day8)
    #expect(try store.hasActiveBatch(level: 1) == false)
}

@Test func testDropMissedLooksAdvancesOverdueFirstLooksAndLeavesTodayAlone() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)

    let overdue = try store.createBatch(level: 1, wordIndices: [1], today: provider(at: date(2026, 1, 1)))
    let dueToday = try store.createBatch(level: 1, wordIndices: [2], today: provider(at: date(2026, 1, 4)))
    let today = provider(at: date(2026, 1, 5))

    try store.dropMissedLooks(today: today)

    let overdueID = try #require(overdue.id)
    let skipped = try #require(try store.fetchBatch(id: overdueID))
    #expect(skipped.lookNumber == 1)
    #expect(skipped.nextLookOn == localDate(2026, 1, 12))

    let dueTodayID = try #require(dueToday.id)
    let stillDue = try #require(try store.fetchBatch(id: dueTodayID))
    #expect(stillDue.lookNumber == 0)
    #expect(stillDue.nextLookOn == localDate(2026, 1, 5))
    #expect(try store.dueBatches(today: today).map(\.id) == [dueToday.id])
}

@Test func testDropMissedLooksRetiresAnOverdueSecondLook() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let created = try store.createBatch(level: 1, wordIndices: [1], today: provider(at: date(2026, 1, 1)))
    let batchID = try #require(created.id)
    try store.recordLook(batchID: batchID, today: provider(at: date(2026, 1, 2)))

    try store.dropMissedLooks(today: provider(at: date(2026, 1, 20)))

    let fetched = try #require(try store.fetchBatch(id: batchID))
    #expect(fetched.isRetired == true)
}

@Test func testDueBatchesOnALaterDayDoNotIncludeAMissedLook() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    try store.createBatch(level: 1, wordIndices: [1], today: provider(at: date(2026, 1, 1)))

    #expect(try store.dueBatches(today: provider(at: date(2026, 1, 2))).count == 1)
    #expect(try store.dueBatches(today: provider(at: date(2026, 1, 3))).isEmpty)
}
