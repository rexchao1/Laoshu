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
