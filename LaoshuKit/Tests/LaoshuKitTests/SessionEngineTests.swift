import Foundation
import Testing
import GRDB
@testable import LaoshuKit

/// Drives `TodayProvider` with a fixed clock instead of the system one, so
/// which batches are due is deterministic (mirrors `BatchTests.swift`).
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

@Test func testSessionDrawsEightUnseenAtRandom() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 8)
    var seen: [Int] = []
    while let card = session.currentCard {
        seen.append(card.word.wordIndex)
        try session.swipe(.right)
    }
    #expect(seen.count == 8)
    #expect(Set(seen).count == 8)
    #expect(seen.allSatisfy { (1...20).contains($0) })
}

/// D17a: the draw is a sample of the level, not its opening run. Asserting
/// the negative is the point; an accidental return to `ORDER BY word_index`
/// would still pass every other test in this file.
@Test func testDrawIsNotTheEightLowestIndexes() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 200)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    var seen: [Int] = []
    while let card = session.currentCard {
        seen.append(card.word.wordIndex)
        try session.swipe(.right)
    }
    #expect(seen != [1, 2, 3, 4, 5, 6, 7, 8])
    #expect(seen != seen.sorted())
}

@Test func testSameSeedDrawsTheSameWords() throws {
    let first = try TestFixtures.makeDatabase(wordCount: 200)
    let second = try TestFixtures.makeDatabase(wordCount: 200)

    func draw(_ dbQueue: GRDB.DatabaseQueue) throws -> [Int] {
        let session = try TestFixtures.makeEngine(dbQueue: dbQueue, seed: 7).startSession(level: 1)
        var seen: [Int] = []
        while let card = session.currentCard {
            seen.append(card.word.wordIndex)
            try session.swipe(.right)
        }
        return seen
    }

    #expect(try draw(first) == draw(second))
}

@Test func testRightSwipeFinishesWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    // Which word comes up first is now the shuffle's business (D17a), so the
    // test reads it rather than assuming it.
    let first = try #require(session.currentCard?.word.wordIndex)

    try session.swipe(.right)

    #expect(session.finishedCount == 1)
    #expect(session.currentCard?.word.wordIndex != first)
    #expect(try BatchStore(dbQueue: dbQueue).isIntroduced(wordIndex: first))
}

@Test func testLeftSwipeRequeuesAtLeastThreeCardsLater() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    let sent = try #require(session.currentCard?.word.wordIndex)
    try session.swipe(.left)

    // Three other cards must be shown before the left-swiped word comes back.
    for _ in 0..<3 {
        #expect(session.currentCard?.word.wordIndex != sent)
        try session.swipe(.right)
    }

    #expect(session.currentCard?.word.wordIndex == sent)
}

@Test func testThirdLeftSwipeParksWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 1)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 1)

    try session.swipe(.left) // 1st left: only card left, shown again immediately
    #expect(!session.isFinished)
    #expect(session.currentCard?.word.wordIndex == 1)

    try session.swipe(.left) // 2nd left
    #expect(!session.isFinished)
    #expect(session.currentCard?.word.wordIndex == 1)

    try session.swipe(.left) // 3rd left: parked, not requeued
    #expect(session.isFinished)
    #expect(session.parkedCount == 1)
    #expect(session.finishedCount == 0)
}

@Test func testShortLevelEndsEarlyAndReportsCount() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 5)
    var seen: [Int] = []
    while let card = session.currentCard {
        seen.append(card.word.wordIndex)
        try session.swipe(.right)
    }
    #expect(seen.sorted() == [1, 2, 3, 4, 5])
}

@Test func testLevelSummariesReportsPerLevelCounts() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 3, 2: 2, 3: 5])
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let summaries = try engine.levelSummaries()

    #expect(summaries == [
        LevelSummary(level: 1, wordCount: 3),
        LevelSummary(level: 2, wordCount: 2),
        LevelSummary(level: 3, wordCount: 5),
    ])
}

// MARK: - Showing what is waiting

@Test func testLevelSummariesCountWordsFromDueBatchesButNotTheEightNewWordsASessionWouldAdd() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 20, 2: 20])
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let day1 = provider(at: date(2026, 1, 2))

    // Level 1 has a due batch of 3; level 2 has a batch not due until later.
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    try store.createBatch(level: 2, wordIndices: [21, 22], today: day1)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    let summaries = try engine.levelSummaries()

    #expect(summaries.first { $0.level == 1 }?.waitingCount == 3)
    #expect(summaries.first { $0.level == 2 }?.waitingCount == 0)
}

@Test func testLevelSummariesRecomputeAsOfEachCall() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let day1 = provider(at: date(2026, 1, 2))

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    #expect(try engine.levelSummaries().first?.waitingCount == 0)

    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    // Same engine instance, called again: the count reflects the batch
    // created since the first call, not a value cached at construction.
    #expect(try engine.levelSummaries().first?.waitingCount == 3)
}

// MARK: - The summary's schedule line and the eight-more button

@Test func testSessionReportsWhenItsNewWordsComeBack() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let day0 = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)

    let session = try engine.startSession(level: 1)
    #expect(session.newWordsReturnOn == localDate(2026, 1, 2))
}

@Test func testSessionHoldingOnlyADueBatchNamesNoReturnDate() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let day0 = provider(at: date(2026, 1, 1))
    try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let day1 = provider(at: date(2026, 1, 2))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 3) // the due batch's words; none left unseen to draw as new
    #expect(session.newWordsReturnOn == nil)
}

@Test func testHasUnseenWordsRemainingIsFalseOnceASessionsOwnDrawExhaustsThePool() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)
    #expect(session.drawnCount == 8)
    #expect(session.hasUnseenWordsRemaining == false)
}

@Test func testHasUnseenWordsRemainingIsTrueWhenThePoolOutlastsTheDraw() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)
    #expect(session.drawnCount == 8)
    #expect(session.hasUnseenWordsRemaining == true)
}

@Test func testAllowanceSpentEmptySessionReportsUnseenWordsRemaining() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let session = try engine.startSession(level: 1)

    #expect(session.emptyReason == .allowanceSpent)
    #expect(session.hasUnseenWordsRemaining == true)
}

@Test func testWaitingOnLadderEmptySessionReportsNoUnseenWordsAndTheNextReturnDate() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let session = try engine.startSession(level: 1)

    #expect(session.emptyReason == .waitingOnLadder)
    #expect(session.hasUnseenWordsRemaining == false)
    #expect(session.nextBatchReturnOn == localDate(2026, 1, 2))
}

@Test func testLevelCompleteEmptySessionReportsNoUnseenWordsAndNoReturnDate() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    let day1 = provider(at: date(2026, 1, 2))
    try store.recordLook(batchID: batchID, today: day1)
    let day8 = provider(at: date(2026, 1, 9))
    try store.recordLook(batchID: batchID, today: day8) // retires

    let afterRetirement = provider(at: date(2026, 1, 10))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: afterRetirement)
    let session = try engine.startSession(level: 1)

    #expect(session.emptyReason == .levelComplete)
    #expect(session.hasUnseenWordsRemaining == false)
    #expect(session.nextBatchReturnOn == nil)
}

@Test func testBonusSessionIgnoresTheAllowanceAndDrawsEightMoreNewWords() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))

    // Spend today's allowance with an ordinary session first, finishing it
    // so its `session` row is `done` rather than `live` — the bonus session
    // below is a second live session on the same level, which the schema
    // only allows once the first has stopped being live.
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let first = try engine.startSession(level: 1)
    while first.currentCard != nil {
        try first.swipe(.right)
    }
    #expect(try store.hasBatchCreatedToday(today: day0) == true)

    let bonus = try engine.startBonusSession(level: 1)
    #expect(bonus.drawnCount == 8)

    var seen: [Int] = []
    while let card = bonus.currentCard {
        seen.append(card.word.wordIndex)
        try bonus.swipe(.right)
    }
    #expect(Set(seen).count == 8)

    // Its first swipe writes a second batch on the same level, dated the
    // same day as the first, holding exactly the words it drew.
    let batchIDs = try dbQueue.read { db in
        try Int64.fetchAll(db, sql: "SELECT id FROM batch WHERE level = 1 AND created_on = ?;", arguments: [day0.today()])
    }
    #expect(batchIDs.count == 2)
    let secondBatchWords = try store.wordIndices(batchIDs: [try #require(batchIDs.last)])
    #expect(Set(secondBatchWords) == Set(seen))
}

@Test func testFirstAttemptRightCountOnlyCountsCleanSwipes() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    try session.swipe(.right) // 1st card: right first try
    try session.swipe(.left)  // 2nd card: goes left once
    try session.swipe(.right) // 3rd card: right first try
    try session.swipe(.right) // 2nd card comes back, now right after a left

    #expect(session.finishedCount == 3)
    #expect(session.firstAttemptRightCount == 2)
}

@Test func testParkedWordsRecordsTheWordThatParked() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 1)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    try session.swipe(.left)
    try session.swipe(.left)
    try session.swipe(.left)

    #expect(session.parkedWords.map(\.wordIndex) == [1])
}

@Test func testRequeuedCardIsPresentedFrontSide() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    let sent = try #require(session.currentCard?.word.wordIndex)
    session.flipCurrentCard()
    #expect(session.currentCard?.isFlipped == true)

    try session.swipe(.left)

    // The left-swiped word reappears after three other cards.
    try session.swipe(.right)
    try session.swipe(.right)
    try session.swipe(.right)

    #expect(session.currentCard?.word.wordIndex == sent)
    #expect(session.currentCard?.isFlipped == false)
}

@Test func testFlipTurnsTheCardBothWays() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    #expect(session.currentCard?.isFlipped == false)
    #expect(session.currentCard?.hasBeenRevealed == false)

    session.flipCurrentCard()
    #expect(session.currentCard?.isFlipped == true)
    #expect(session.currentCard?.hasBeenRevealed == true)

    // D26a: flipping back shows the pinyin again without un-revealing the
    // meaning, which is what keeps the card gradable.
    session.flipCurrentCard()
    #expect(session.currentCard?.isFlipped == false)
    #expect(session.currentCard?.hasBeenRevealed == true)

    session.flipCurrentCard()
    #expect(session.currentCard?.isFlipped == true)
    #expect(session.currentCard?.hasBeenRevealed == true)
}

@Test func testRequeueTakesBackTheReveal() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    let sent = try #require(session.currentCard?.word.wordIndex)
    session.flipCurrentCard()
    try session.swipe(.left)

    try session.swipe(.right)
    try session.swipe(.right)
    try session.swipe(.right)

    // A requeued card is a fresh presentation, so it must be recalled again
    // before it can be graded (D20, D26a).
    #expect(session.currentCard?.word.wordIndex == sent)
    #expect(session.currentCard?.hasBeenRevealed == false)
}

// MARK: - Composing a session from due batches and the day's new words

@Test func testSessionHoldsDueBatchWordsAndNewWordsInOneShuffledReproduciblePool() throws {
    let day0 = provider(at: date(2026, 1, 1))
    let day1 = provider(at: date(2026, 1, 2))

    func draw() throws -> [Int] {
        let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
        try BatchStore(dbQueue: dbQueue).createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

        let engine = TestFixtures.makeEngine(dbQueue: dbQueue, seed: 7, today: day1)
        let session = try engine.startSession(level: 1)
        var seen: [Int] = []
        while let card = session.currentCard {
            seen.append(card.word.wordIndex)
            try session.swipe(.right)
        }
        return seen
    }

    let first = try draw()
    let second = try draw()

    // The due batch's three words plus eight new ones, all in one pool.
    #expect(first.count == 11)
    #expect(Set([1, 2, 3]).isSubset(of: Set(first)))
    #expect(Set(first).subtracting([1, 2, 3]).count == 8)

    // Reproducible under the same seed.
    #expect(first == second)
}

@Test func testWordParkedByThreeLeftSwipesIsNeverDrawnAsNewAgain() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 2)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))

    // Word 2 already belongs to a batch retired well before today, so it
    // neither spends today's allowance nor is ever due again — it should
    // never be offered as new either, though that isn't today's story.
    let earlierCreation = provider(at: date(2025, 12, 1))
    let earlierFirstLook = provider(at: date(2025, 12, 2))
    let earlierSecondLook = provider(at: date(2025, 12, 9))
    let earlierBatch = try store.createBatch(level: 1, wordIndices: [2], today: earlierCreation)
    let earlierBatchID = try #require(earlierBatch.id)
    try store.recordLook(batchID: earlierBatchID, today: earlierFirstLook)
    try store.recordLook(batchID: earlierBatchID, today: earlierSecondLook)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let session = try engine.startSession(level: 1)

    // The only unseen word left is word 1.
    #expect(session.drawnCount == 1)
    #expect(session.currentCard?.word.wordIndex == 1)

    try session.swipe(.left) // 1st left
    try session.swipe(.left) // 2nd left
    try session.swipe(.left) // 3rd left: parked, not requeued

    #expect(session.isFinished)
    #expect(session.parkedCount == 1)
    #expect(try store.isIntroduced(wordIndex: 1) == true)

    // Nothing is unseen at all now, so a fresh draw the same day holds no
    // cards — the parked word never comes back as new.
    let again = try engine.startSession(level: 1)
    #expect(again.drawnCount == 0)
}

@Test func testAbandonedSessionLeavesNoBatchAndWordsReturnAsNewTheNextDay() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day0 = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, seed: 3, today: day0)

    let first = try engine.startSession(level: 1)
    #expect(first.drawnCount == 8)
    // Abandoned: never swiped.

    let store = BatchStore(dbQueue: dbQueue)
    #expect(try store.hasBatchCreatedToday(today: day0) == false)
    for index in 1...8 {
        #expect(try store.isIntroduced(wordIndex: index) == false)
    }

    let day1 = provider(at: date(2026, 1, 2))
    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, seed: 3, today: day1)
    let second = try secondEngine.startSession(level: 1)

    #expect(second.drawnCount == 8)
    var seen: [Int] = []
    while let card = second.currentCard {
        seen.append(card.word.wordIndex)
        try second.swipe(.right)
    }
    #expect(Set(seen) == Set(1...8))
}

@Test func testEnteringAndLeavingWithoutSwipingWritesNothingAndSpendsNoAllowance() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    let day1 = provider(at: date(2026, 1, 2))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)

    let session = try engine.startSession(level: 1)
    #expect(session.drawnCount > 0) // the due batch's words plus new ones
    // Abandoned: never swiped.

    let untouched = try #require(try store.fetchBatch(id: batchID))
    #expect(untouched.lookNumber == 0)
    #expect(untouched.nextLookOn == localDate(2026, 1, 2))
    #expect(try store.hasBatchCreatedToday(today: day1) == false)
    #expect(try store.dueBatches(level: 1, today: day1).map(\.id) == [batchID])
}

@Test func testSingleSwipeAdvancesADueBatchsLadderEvenIfTheSessionIsAbandoned() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    let day1 = provider(at: date(2026, 1, 2))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    let session = try engine.startSession(level: 1)

    try session.swipe(.right) // one swipe only, then abandoned

    let advanced = try #require(try store.fetchBatch(id: batchID))
    #expect(advanced.lookNumber == 1)
    #expect(advanced.nextLookOn == localDate(2026, 1, 9)) // day 1 + 7
}

@Test func testAllowanceSpentAtOneLevelLeavesAnotherLevelsDueBatchesButNoNewWords() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 8, 2: 8])
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let day1 = provider(at: date(2026, 1, 2))

    try store.createBatch(level: 2, wordIndices: [9, 10, 11], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)

    // Spend the day's allowance by drawing and committing level 1's batch.
    let level1Session = try engine.startSession(level: 1)
    #expect(level1Session.drawnCount == 8)
    try level1Session.swipe(.right)

    #expect(try store.hasBatchCreatedToday(today: day1) == true)

    // Level 2 still gets its due batch's words, but no new words.
    let level2Session = try engine.startSession(level: 2)
    #expect(level2Session.drawnCount == 3)
    var seen: [Int] = []
    while let card = level2Session.currentCard {
        seen.append(card.word.wordIndex)
        try level2Session.swipe(.right)
    }
    #expect(Set(seen) == Set([9, 10, 11]))
}

// MARK: - The three zero-card states

@Test func testEmptySessionDistinguishesAllowanceSpentFromNoDueBatch() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))

    // Spends today's allowance, leaving words 4-8 unseen but no due batch.
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 0)
    #expect(session.emptyReason == .allowanceSpent)
}

@Test func testEmptySessionDistinguishesWaitingOnLadderFromLevelComplete() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))

    // Every word is introduced, but the batch isn't due until tomorrow.
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 0)
    #expect(session.emptyReason == .waitingOnLadder)
}

@Test func testEmptySessionDistinguishesLevelCompleteFromWaitingOnLadder() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    let day1 = provider(at: date(2026, 1, 2))
    try store.recordLook(batchID: batchID, today: day1)

    let day8 = provider(at: date(2026, 1, 9))
    try store.recordLook(batchID: batchID, today: day8) // retires

    let afterRetirement = provider(at: date(2026, 1, 10))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: afterRetirement)
    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 0)
    #expect(session.emptyReason == .levelComplete)
}

/// The eight-more button is hidden when a level has no unseen words left
/// (D19, D22), but nothing in the engine's API enforces that. Asking for a
/// bonus session anyway must name a reason rather than hand back a drawn
/// count of zero, which renders "0 of 0 right the first time" — the screen
/// D22 exists to remove.
@Test func testBonusSessionOnAnExhaustedLevelNamesAReasonRatherThanDrawingNothing() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    // Every word introduced, one look taken, so a batch is still on the
    // ladder and the level is not finished.
    let day1 = provider(at: date(2026, 1, 2))
    try store.recordLook(batchID: batchID, today: day1)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    let bonus = try engine.startBonusSession(level: 1)

    #expect(bonus.drawnCount == 0)
    #expect(bonus.emptyReason == .waitingOnLadder)
    #expect(bonus.nextBatchReturnOn == localDate(2026, 1, 9))
    #expect(bonus.hasUnseenWordsRemaining == false)
}

// MARK: - Reading back the words already met in a level

/// A snapshot of every row in the tables a swipe or a batch write could
/// touch, for asserting `browse` leaves them untouched.
private struct WriteSnapshot: Equatable {
    let review: [Row]
    let batch: [Row]
    let batchWord: [Row]
    let placement: [Row]
    let session: [Row]
    let sessionCard: [Row]

    init(_ dbQueue: DatabaseQueue) throws {
        review = try dbQueue.read { try Row.fetchAll($0, sql: "SELECT * FROM review ORDER BY rowid;") }
        batch = try dbQueue.read { try Row.fetchAll($0, sql: "SELECT * FROM batch ORDER BY id;") }
        batchWord = try dbQueue.read { try Row.fetchAll($0, sql: "SELECT * FROM batch_word ORDER BY batch_id, word_index;") }
        placement = try dbQueue.read { try Row.fetchAll($0, sql: "SELECT * FROM placement ORDER BY id;") }
        session = try dbQueue.read { try Row.fetchAll($0, sql: "SELECT * FROM session ORDER BY id;") }
        sessionCard = try dbQueue.read { try Row.fetchAll($0, sql: "SELECT * FROM session_card ORDER BY session_id, word_index;") }
    }

    static func == (lhs: WriteSnapshot, rhs: WriteSnapshot) -> Bool {
        lhs.review == rhs.review && lhs.batch == rhs.batch
            && lhs.batchWord == rhs.batchWord && lhs.placement == rhs.placement
            && lhs.session == rhs.session && lhs.sessionCard == rhs.sessionCard
    }
}

@Test func testBrowseListsEveryWordInEveryBatchOfTheLevel() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 10)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    try store.createBatch(level: 1, wordIndices: [4, 5], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(Set(result.words.map(\.wordIndex)) == Set([1, 2, 3, 4, 5]))
    #expect(result.emptyReason == nil)
}

@Test func testBrowseReturnsDefinitionAndGlossForEveryWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 2)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    let byIndex = Dictionary(uniqueKeysWithValues: result.words.map { ($0.wordIndex, $0) })
    #expect(byIndex[1]?.definition == "word 1")
    #expect(byIndex[1]?.gloss == "gloss 1")
    #expect(byIndex[2]?.definition == "word 2")
    #expect(byIndex[2]?.gloss == "gloss 2")
}

@Test func testBrowseIncludesWordsFromRetiredBatches() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    let day1 = provider(at: date(2026, 1, 2))
    try store.recordLook(batchID: batchID, today: day1)
    let day8 = provider(at: date(2026, 1, 9))
    try store.recordLook(batchID: batchID, today: day8) // retires

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(Set(result.words.map(\.wordIndex)) == Set([1, 2, 3]))
}

@Test func testBrowseExcludesWordsBelongingToNoBatch() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(Set(result.words.map(\.wordIndex)) == Set([1, 2, 3]))
}

@Test func testBrowseExcludesOtherLevels() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 5, 2: 5])
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2], today: day0)
    try store.createBatch(level: 2, wordIndices: [6, 7], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(Set(result.words.map(\.wordIndex)) == Set([1, 2]))
}

@Test func testBrowseOrdersSameDayBatchesByIDDescending() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 10)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2], today: day0)
    let newer = try store.createBatch(level: 1, wordIndices: [3, 4], today: day0)
    #expect(newer.createdOn == localDate(2026, 1, 1))

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(result.words.map(\.wordIndex) == [3, 4, 1, 2])
}

@Test func testBrowseOrdersBatchesByDateDescending() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 10)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let day1 = provider(at: date(2026, 1, 2))
    try store.createBatch(level: 1, wordIndices: [1, 2], today: day0)
    try store.createBatch(level: 1, wordIndices: [3, 4], today: day1)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(result.words.map(\.wordIndex) == [3, 4, 1, 2])
}

@Test func testBrowseOrdersWithinABatchByWordIndexAscending() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 10)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [5, 1, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let result = try engine.browse(level: 1)

    #expect(result.words.map(\.wordIndex) == [1, 3, 5])
}

@Test func testBrowseOnALevelWithNoBatchesCarriesTheReason() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let result = try engine.browse(level: 1)

    #expect(result.words.isEmpty)
    #expect(result.emptyReason == .levelHasNoBatches)
}

@Test func testBrowseWritesNothing() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 10)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let before = try WriteSnapshot(dbQueue)

    _ = try engine.browse(level: 1)

    let after = try WriteSnapshot(dbQueue)
    #expect(before == after)
}

@Test func testBrowseDoesNotSpendTheDaysAllowance() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let day0 = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)

    _ = try engine.browse(level: 1)

    let session = try engine.startSession(level: 1)
    #expect(session.drawnCount == 8)
}

@Test func testBrowseDoesNotAdvanceADueBatch() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 10)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let created = try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    let batchID = try #require(created.id)

    let day1 = provider(at: date(2026, 1, 2))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    _ = try engine.browse(level: 1)

    let untouched = try #require(try store.fetchBatch(id: batchID))
    #expect(untouched.nextLookOn == localDate(2026, 1, 2))
    #expect(untouched.lookNumber == 0)
}

@Test func testBrowseListsAllEightWordsOfAnAbandonedSessionsBatch() throws {
    // Exactly eight words in the level, so the pool the session draws from
    // and the eight it draws are the same set regardless of shuffle order —
    // letting the test know the full drawn set without draining the queue.
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day0 = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)

    let session = try engine.startSession(level: 1)
    #expect(session.drawnCount == 8)
    try session.swipe(.right) // one swipe writes the batch; the rest is abandoned

    let result = try engine.browse(level: 1)
    #expect(Set(result.words.map(\.wordIndex)) == Set(1...8))
    #expect(result.words.count == 8)
}

// MARK: - D9, D10, D13c: drawing the configured number of new words

@Test func testSessionDrawsTheConfiguredNumberOfUnseenWords() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    try PreferenceStore(dbQueue: dbQueue).setNewWordsPerDay(4)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 4)
}

@Test func testSessionDrawsTwentyAtTheHighEndOfTheSetting() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 40)
    try PreferenceStore(dbQueue: dbQueue).setNewWordsPerDay(20)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 20)
}

@Test func testBonusSessionDrawsTheConfiguredNumberOfUnseenWords() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 40)
    try PreferenceStore(dbQueue: dbQueue).setNewWordsPerDay(20)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let bonus = try engine.startBonusSession(level: 1)

    #expect(bonus.drawnCount == 20)
}

@Test func testSessionDrawsWhatIsLeftWhenTheLevelHasFewerUnseenWordsThanTheSetting() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    try PreferenceStore(dbQueue: dbQueue).setNewWordsPerDay(20)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 5)
}

@Test func testSessionCarriesTheSizeAndSpeakOnFlipItWasDrawnWith() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let store = PreferenceStore(dbQueue: dbQueue)
    try store.setNewWordsPerDay(12)
    try store.setSpeakOnFlip(false)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)
    #expect(session.newWordsPerDay == 12)
    #expect(session.speakOnFlip == false)

    // Writing the settings underneath an already-drawn session must not
    // move what it already carries (D13c).
    try store.setNewWordsPerDay(4)
    try store.setSpeakOnFlip(true)
    #expect(session.newWordsPerDay == 12)
    #expect(session.speakOnFlip == false)
}

@Test func testSessionCarriesSpeakOnFlipTrueWhenSetThatWay() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    try PreferenceStore(dbQueue: dbQueue).setSpeakOnFlip(true)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.speakOnFlip == true)
}

@Test func testAllowanceSpentEmptySessionStillCarriesTheConfiguredSizeRatherThanZero() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = BatchStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    try store.createBatch(level: 1, wordIndices: [1, 2, 3], today: day0)
    try PreferenceStore(dbQueue: dbQueue).setNewWordsPerDay(12)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 0)
    #expect(session.emptyReason == .allowanceSpent)
    #expect(session.newWordsPerDay == 12)
}

@Test func testAllowanceIsStillOneBatchADayRegardlessOfARaisedSettingAfterTheDraw() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 8, 2: 20])
    let store = PreferenceStore(dbQueue: dbQueue)
    let day0 = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)

    // Draw at the default of eight and swipe once, so the batch is written.
    let first = try engine.startSession(level: 1)
    #expect(first.drawnCount == 8)
    try first.swipe(.right)

    // Raise the setting after the allowance is already spent for the day.
    try store.setNewWordsPerDay(20)

    let second = try engine.startSession(level: 2)
    #expect(second.drawnCount == 0)
    #expect(second.emptyReason == .allowanceSpent)
}

@Test func testBrowseReadsADatabaseWrittenByThePreviousVersion() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint2ReviewLog(
        at: reviewLogURL,
        batches: [
            (level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: nil, lookNumber: 2, wordIndices: [1, 2, 3]),
        ]
    )

    let today = provider(at: date(2026, 1, 3))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)

    let result = try engine.browse(level: 1)

    #expect(Set(result.words.map(\.wordIndex)) == Set([1, 2, 3]))
}

// MARK: - Writing a session down as it is swiped (D4a, D8, D11, D11b, D12, D12a, D16)

/// A clock whose instant can move mid-test, so a test can put the draw on
/// one side of a day boundary and the first swipe on the other — a single
/// fixed-instant `TodayProvider` (`provider(at:)`) cannot do this since draw
/// and swipe would read the same instant.
private final class MutableClock: @unchecked Sendable {
    var instant: Date
    init(_ instant: Date) { self.instant = instant }
}

@Test func testEnteringAndLeavingWithoutSwipingWritesNoSessionRow() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)
    #expect(session.drawnCount == 8)
    // Abandoned: never swiped.

    let store = SessionStore(dbQueue: dbQueue)
    #expect(try store.liveSession(level: 1) == nil)
    let sessionCount = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM session;") }
    #expect(sessionCount == 0)
}

@Test func testASwipeWhoseWriteThrowsLeavesTheCardAtTheHeadOfTheQueue() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)
    let first = try #require(session.currentCard?.word.wordIndex)

    // A live session already parked on the level trips
    // `session_one_live_per_level` the moment this session's first swipe
    // tries to insert its own session row.
    let store = SessionStore(dbQueue: dbQueue)
    try store.insertSession(StoredSession(
        level: 1, createdOn: localDate(2026, 1, 1), direction: .receptive, speakOnFlip: true,
        status: .live, cards: [StoredSessionCard(wordIndex: 1, position: 0)]
    ))

    #expect(throws: (any Error).self) {
        try session.swipe(.right)
    }

    #expect(session.currentCard?.word.wordIndex == first)
    #expect(session.isFinished == false)
    #expect(session.finishedCount == 0)
    #expect(session.drawnCount == 8)

    // Only the pre-existing session's row is on the level — this session's
    // own write left nothing behind.
    let liveCards = try #require(try store.liveSession(level: 1)?.cards)
    #expect(liveCards.count == 1)
}

@Test func testALeftSwipedCardResumesAtThePlaceTheLeftSwipePutIt() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)
    let sent = try #require(session.currentCard?.word.wordIndex)

    try session.swipe(.left) // requeued at min(3, 7) == 3

    let store = SessionStore(dbQueue: dbQueue)
    let stored = try #require(try store.liveSession(level: 1))
    let pending = stored.cards.filter { $0.outcome == nil }

    #expect(pending.count == 8)
    #expect(pending.map(\.position) == Array(0..<8))
    #expect(pending[3].wordIndex == sent)
    #expect(session.currentCard?.word.wordIndex == pending[0].wordIndex)
}

@Test func testParkedWordsKeepTheirOrderAcrossAResume() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    // Left-swipe whatever is current until exactly two words have parked,
    // leaving the third still pending so the session stays live.
    while session.parkedCount < 2 {
        try session.swipe(.left)
    }
    #expect(session.isFinished == false)
    #expect(session.parkedWords.map(\.wordIndex).count == 2)

    let store = SessionStore(dbQueue: dbQueue)
    let stored = try #require(try store.liveSession(level: 1))
    let settled = stored.cards
        .filter { $0.outcome != nil }
        .sorted { $0.settledOrder! < $1.settledOrder! }

    #expect(settled.map(\.wordIndex) == session.parkedWords.map(\.wordIndex))
    #expect(settled.allSatisfy { $0.outcome == .parked })
}

@Test func testAFinishedSessionIsMarkedDoneAndIsNotResumed() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    while session.currentCard != nil {
        try session.swipe(.right)
    }
    #expect(session.isFinished)

    let store = SessionStore(dbQueue: dbQueue)
    #expect(try store.liveSession(level: 1) == nil)

    let status = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT status FROM session WHERE level = 1;")
    }
    #expect(status == "done")
}

@Test func testTheSummaryNamesTheReturnDateTheBatchHoldsWhenTheFirstSwipeCrossesMidnight() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)

    // The draw happens just before midnight; the first swipe lands just
    // after. Business day stays the same across that boundary (it turns at
    // 04:00), but D4a's wall-clock floor turns right at midnight, so the
    // batch's first look computed at the draw is one day earlier than the
    // one actually written by the swipe.
    let drawInstant = testCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 55))!
    let swipeInstant = testCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 5))!
    let clock = MutableClock(drawInstant)
    let today = TodayProvider(calendar: testCalendar, clock: { clock.instant })
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)

    let session = try engine.startSession(level: 1)
    let preview = session.newWordsReturnOn
    #expect(preview == localDate(2026, 1, 2))

    clock.instant = swipeInstant
    try session.swipe(.right)

    #expect(session.newWordsReturnOn == localDate(2026, 1, 3))
    #expect(session.newWordsReturnOn != preview)

    // The summary's date matches what the batch itself actually holds.
    let store = SessionStore(dbQueue: dbQueue)
    let stored = try #require(try store.liveSession(level: 1))
    let batchID = try #require(stored.newWordsBatchID)
    let nextLookOn = try dbQueue.read { db in
        try LocalDate.fetchOne(db, sql: "SELECT next_look_on FROM batch WHERE id = ?;", arguments: [batchID])
    }
    #expect(nextLookOn == session.newWordsReturnOn)
}

// MARK: - Picking a session back up where it was left (checkpoint 7)

@Test func testASessionSwipedPartwayComesBackWithTheSameQueueInTheSameOrder() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)

    let original = try engine.startSession(level: 1)
    try original.swipe(.right)
    try original.swipe(.left)

    let store = SessionStore(dbQueue: dbQueue)
    let stored = try #require(try store.liveSession(level: 1))
    let expectedOrder = stored.cards
        .filter { $0.position != nil }
        .sorted { $0.position! < $1.position! }
        .map(\.wordIndex)

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)
    #expect(resumed.isResumed)

    var actual: [Int] = []
    while let card = resumed.currentCard {
        actual.append(card.word.wordIndex)
        try resumed.swipe(.right)
    }
    #expect(actual == expectedOrder)
}

@Test func testAResumedSessionKeepsEachCardsLeftSwipeCount() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let original = try engine.startSession(level: 1)
    let target = try #require(original.currentCard?.word.wordIndex)

    try original.swipe(.left) // requeued to the end with a 3-word queue
    try original.swipe(.right)
    try original.swipe(.right)
    try original.swipe(.left) // target's second left swipe

    #expect(original.currentCard?.word.wordIndex == target)
    #expect(original.currentCard?.leftSwipeCount == 2)
    #expect(original.isFinished == false)

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)

    #expect(resumed.currentCard?.word.wordIndex == target)
    #expect(resumed.currentCard?.leftSwipeCount == 2)
}

@Test func testAResumedSessionsSummaryCountsTheWholeSessionNotJustThePartAfterResuming() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let original = try engine.startSession(level: 1)

    try original.swipe(.right) // finished, first attempt right
    try original.swipe(.left) // requeued, still pending

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)

    #expect(resumed.drawnCount == 5)
    #expect(resumed.finishedCount == 1)
    #expect(resumed.firstAttemptRightCount == 1)
    #expect(resumed.parkedCount == 0)

    while let card = resumed.currentCard {
        _ = card
        try resumed.swipe(.right)
    }

    #expect(resumed.drawnCount == 5)
    #expect(resumed.finishedCount == 5)
}

@Test func testASessionFromAnEarlierBusinessDayIsAbandonedAndAFreshOneDrawn() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day0 = provider(at: date(2026, 1, 1))
    let engine0 = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let yesterday = try engine0.startSession(level: 1)
    try yesterday.swipe(.left)

    let day1 = provider(at: date(2026, 1, 2))
    let engine1 = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)
    let fresh = try engine1.startSession(level: 1)

    #expect(fresh.isResumed == false)
    #expect(fresh.drawnCount == 8)

    let store = SessionStore(dbQueue: dbQueue)
    #expect(try store.liveSession(level: 1) == nil)
    let statuses = try dbQueue.read { db in
        try String.fetchAll(db, sql: "SELECT status FROM session WHERE level = 1 ORDER BY id;")
    }
    #expect(statuses == ["abandoned"])
}

@Test func testASessionOnOneLevelDoesNotDisturbALiveSessionOnAnother() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 8, 2: 8])
    let day = provider(at: date(2026, 1, 1))

    // Level 2 draws from a batch already due today rather than the day's new
    // word allowance, which is spent globally (not per level) the moment
    // level 1 draws its own eight — see
    // testAllowanceSpentAtOneLevelLeavesAnotherLevelsDueBatchesButNoNewWords.
    let batchStore = BatchStore(dbQueue: dbQueue)
    let dayBefore = provider(at: date(2025, 12, 31))
    try batchStore.createBatch(level: 2, wordIndices: [9, 10, 11], today: dayBefore)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)

    let level1 = try engine.startSession(level: 1)
    try level1.swipe(.left)
    let level2 = try engine.startSession(level: 2)
    try level2.swipe(.right)

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed1 = try secondEngine.startSession(level: 1)
    let resumed2 = try secondEngine.startSession(level: 2)

    #expect(resumed1.isResumed)
    #expect(resumed2.isResumed)
    #expect(resumed1.drawnCount == 8)
    #expect(resumed2.drawnCount == 3)
    #expect(resumed1.finishedCount == 0)
    #expect(resumed2.finishedCount == 1)
}

@Test func testAResumedSessionKeepsTheSettingsItWasDrawnWith() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day = provider(at: date(2026, 1, 1))
    let preferenceStore = PreferenceStore(dbQueue: dbQueue)
    try preferenceStore.setDirection(.reverse)
    try preferenceStore.setSpeakOnFlip(false)

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let original = try engine.startSession(level: 1)
    #expect(original.direction == .reverse)
    #expect(original.speakOnFlip == false)
    try original.swipe(.left)

    // Settings change after the draw; the resumed session keeps what it was
    // drawn with, not whatever preferences say now (D25).
    try preferenceStore.setDirection(.receptive)
    try preferenceStore.setSpeakOnFlip(true)

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)

    #expect(resumed.direction == .reverse)
    #expect(resumed.speakOnFlip == false)
}

@Test func testADrawOnANewDayRetiresYesterdaysRowAndWritesNothingElse() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day0 = provider(at: date(2026, 1, 1))
    let engine0 = TestFixtures.makeEngine(dbQueue: dbQueue, today: day0)
    let yesterday = try engine0.startSession(level: 1)
    try yesterday.swipe(.left)

    let day1 = provider(at: date(2026, 1, 2))
    let engine1 = TestFixtures.makeEngine(dbQueue: dbQueue, today: day1)

    let beforeReview = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM review ORDER BY rowid;") }
    let beforeBatch = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM batch ORDER BY id;") }
    let beforeCards = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM session_card ORDER BY session_id, word_index;") }

    _ = try engine1.startSession(level: 1)

    let afterReview = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM review ORDER BY rowid;") }
    let afterBatch = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM batch ORDER BY id;") }
    let afterCards = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM session_card ORDER BY session_id, word_index;") }
    #expect(beforeReview == afterReview)
    #expect(beforeBatch == afterBatch)
    #expect(beforeCards == afterCards)

    let sessionRows = try dbQueue.read { db in try Row.fetchAll(db, sql: "SELECT id, status FROM session ORDER BY id;") }
    #expect(sessionRows.count == 1)
    #expect((sessionRows[0]["status"] as String) == "abandoned")
}

@Test func testAFutureDatedLiveSessionIsRetiredRatherThanBlockingTheLevel() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    try store.insertSession(StoredSession(
        level: 1, createdOn: localDate(2026, 1, 5), direction: .receptive, speakOnFlip: true,
        status: .live, cards: (1...8).map { StoredSessionCard(wordIndex: $0, position: $0 - 1) }
    ))

    let today = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)
    let session = try engine.startSession(level: 1)

    #expect(session.isResumed == false)
    #expect(session.drawnCount == 8)

    let status = try dbQueue.read { db in try String.fetchOne(db, sql: "SELECT status FROM session WHERE level = 1;") }
    #expect(status == "abandoned")
}

@Test func testAResumedSessionNamesTheReturnDateTheBatchActuallyHolds() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let original = try engine.startSession(level: 1)
    try original.swipe(.right)
    let expectedReturnOn = original.newWordsReturnOn

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)

    #expect(resumed.newWordsReturnOn != nil)
    #expect(resumed.newWordsReturnOn == expectedReturnOn)
}

@Test func testASessionDrawnBeforeAndFirstSwipedAfterTheDayBoundaryIsResumable() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let drawInstant = testCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 55))!
    let swipeInstant = testCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 5))!
    let resumeInstant = testCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 2, minute: 0))!
    let clock = MutableClock(drawInstant)
    let today = TodayProvider(calendar: testCalendar, clock: { clock.instant })
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)

    let original = try engine.startSession(level: 1)
    clock.instant = swipeInstant
    try original.swipe(.left)

    clock.instant = resumeInstant
    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)
    let resumed = try secondEngine.startSession(level: 1)

    #expect(resumed.isResumed)
    #expect(resumed.drawnCount == 8)
}

@Test func testAResumeWhoseWordsNoLongerResolveAbandonsTheSessionAndDrawsFresh() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    let day = provider(at: date(2026, 1, 1))
    try store.insertSession(StoredSession(
        level: 1, createdOn: localDate(2026, 1, 1), direction: .receptive, speakOnFlip: true,
        status: .live, cards: [
            StoredSessionCard(wordIndex: 1, position: 0),
            StoredSessionCard(wordIndex: 999, position: 1),
        ]
    ))

    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let session = try engine.startSession(level: 1)

    #expect(session.isResumed == false)
    #expect(session.drawnCount == 8)

    let status = try dbQueue.read { db in try String.fetchOne(db, sql: "SELECT status FROM session WHERE level = 1;") }
    #expect(status == "abandoned")
}

// MARK: - Draw more over a live session, and the resumed session's line (checkpoint 7)

@Test func testABonusSessionPersistsAndResumesLikeAnyOther() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)

    let bonus = try engine.startBonusSession(level: 1)
    try bonus.swipe(.right)
    try bonus.swipe(.left)

    let store = SessionStore(dbQueue: dbQueue)
    let stored = try #require(try store.liveSession(level: 1))
    let expectedOrder = stored.cards
        .filter { $0.position != nil }
        .sorted { $0.position! < $1.position! }
        .map(\.wordIndex)

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)
    #expect(resumed.isResumed)

    var actual: [Int] = []
    while let card = resumed.currentCard {
        actual.append(card.word.wordIndex)
        try resumed.swipe(.right)
    }
    #expect(actual == expectedOrder)
}

@Test func testABonusDrawRetiresALiveSessionOnTheSameLevel() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 30)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)

    let original = try engine.startSession(level: 1)
    try original.swipe(.left) // writes the live row, still has pending cards
    let originalID = try #require(original.sessionID)

    let bonus = try engine.startBonusSession(level: 1)
    #expect(bonus.drawnCount == 8)

    let originalStatus = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT status FROM session WHERE id = ?;", arguments: [originalID])
    }
    #expect(originalStatus == "abandoned")

    // The bonus session's own first swipe writes its `session` row without
    // colliding with the now-retired original (`session_one_live_per_level`).
    try bonus.swipe(.right)
    let statuses = try dbQueue.read { db in
        try String.fetchAll(db, sql: "SELECT status FROM session WHERE level = 1 ORDER BY id;")
    }
    #expect(statuses == ["abandoned", "live"])
}

@Test func testABonusDrawOnAnExhaustedLevelLeavesTheLiveSessionAlone() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let day = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)

    let original = try engine.startSession(level: 1)
    try original.swipe(.left) // writes the live row; the level's 8 words are now all seen
    let originalID = try #require(original.sessionID)

    let bonus = try engine.startBonusSession(level: 1)
    #expect(bonus.drawnCount == 0)
    #expect(bonus.emptyReason != nil)

    let status = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT status FROM session WHERE id = ?;", arguments: [originalID])
    }
    #expect(status == "live")
}

@Test func testAResumedSessionsDrawMoreButtonShowsTheCurrentSetting() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 30)
    let day = provider(at: date(2026, 1, 1))
    let preferenceStore = PreferenceStore(dbQueue: dbQueue)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)

    let original = try engine.startSession(level: 1)
    #expect(original.newWordsPerDay == 8)
    try original.swipe(.left)

    try preferenceStore.setNewWordsPerDay(4)

    let secondEngine = TestFixtures.makeEngine(dbQueue: dbQueue, today: day)
    let resumed = try secondEngine.startSession(level: 1)

    #expect(resumed.isResumed)
    #expect(resumed.newWordsPerDay == 4)
}
