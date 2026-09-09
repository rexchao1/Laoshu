import Foundation
import GRDB
import Testing
@testable import LaoshuKit

/// Drives `TodayProvider` with a fixed clock instead of the system one
/// (mirrors `BatchTests.swift`).
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

// MARK: - The pure walk (D1, D5, D7e, D12)

@Test func testFourKnownMovesUpOneLevel() {
    var walk = PlacementTest()
    #expect(PlacementTest.initialStep == .testLevel(2))
    #expect(walk.recordBlock(level: 2, knownCount: 4) == .testLevel(3))
}

@Test func testFiveKnownMovesUpOneLevel() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 2, knownCount: 5) == .testLevel(3))
}

@Test func testZeroKnownMovesDownOneLevel() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 2, knownCount: 0) == .testLevel(1))
}

@Test func testOneKnownMovesDownOneLevel() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 3, knownCount: 1) == .testLevel(2))
}

@Test func testTwoKnownStopsTheWalk() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 4, knownCount: 2) == .finished(recommendedLevel: 4))
}

@Test func testThreeKnownStopsTheWalk() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 4, knownCount: 3) == .finished(recommendedLevel: 4))
}

@Test func testMoveDownAtLevelOneStopsTheWalk() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 1, knownCount: 0) == .finished(recommendedLevel: 1))
}

@Test func testMoveUpAtLevelSixStopsTheWalk() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 6, knownCount: 5) == .finished(recommendedLevel: 6))
}

@Test func testTooFewWordsIsTreatedAsKnownAndMovesUp() {
    var walk = PlacementTest()
    #expect(walk.recordTooFewWords(level: 2) == .testLevel(3))
}

@Test func testTooFewWordsAtLevelSixStopsTheWalk() {
    var walk = PlacementTest()
    #expect(walk.recordTooFewWords(level: 6) == .finished(recommendedLevel: 6))
}

/// Starting at level 2, knowing one of five there and five of five at level
/// 1, recommends level 2 — the level above the one the walk stopped on.
@Test func testDescendingPathRecommendsTheLevelAboveWhereItStopped() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 2, knownCount: 1) == .testLevel(1))
    #expect(walk.recordBlock(level: 1, knownCount: 5) == .finished(recommendedLevel: 2))
}

/// Five of five at level 2 and one of five at level 3 recommends level 3.
@Test func testAscendingPathRecommendsTheLevelWhereItStopped() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 2, knownCount: 5) == .testLevel(3))
    #expect(walk.recordBlock(level: 3, knownCount: 1) == .finished(recommendedLevel: 3))
}

/// The full ascent from level 2 to 6, knowing four or more everywhere, stops
/// after twenty-five words by the level 6 rule and recommends level 6.
@Test func testFullAscentStopsAtLevelSixAfterTwentyFiveWordsAndRecommendsLevelSix() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 2, knownCount: 4) == .testLevel(3))
    #expect(walk.recordBlock(level: 3, knownCount: 4) == .testLevel(4))
    #expect(walk.recordBlock(level: 4, knownCount: 4) == .testLevel(5))
    #expect(walk.recordBlock(level: 5, knownCount: 4) == .testLevel(6))
    #expect(walk.recordBlock(level: 6, knownCount: 5) == .finished(recommendedLevel: 6))
}

/// A move that would return to a level already tested stops instead — even
/// away from the level 1/6 boundary.
@Test func testAMoveThatWouldReturnToATestedLevelStopsInstead() {
    var walk = PlacementTest()
    #expect(walk.recordBlock(level: 2, knownCount: 4) == .testLevel(3))
    // Zero known at level 3 would move down to level 2, already tested.
    #expect(walk.recordBlock(level: 3, knownCount: 0) == .finished(recommendedLevel: 3))
}

// MARK: - Driving real blocks through PlacementSession (D7c, D10)

@Test func testPlacementSessionDrawsFiveWordsAtLevelTwoFromWordsInNoBatch() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 20, 2: 20])
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startPlacementTest()

    var seen: [Int] = []
    for _ in 0..<5 {
        let word = try #require(session.currentWord)
        #expect(word.level == 2)
        seen.append(word.wordIndex)
        try session.answer(.know)
    }
    #expect(Set(seen).count == 5)
}

@Test func testALevelWithFewerThanFiveUnseenWordsSkipsStraightToTheNextLevelsBlock() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [2: 3, 3: 20])
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)
    let session = try engine.startPlacementTest()

    let word = try #require(session.currentWord)
    #expect(word.level == 3)

    // Level 2's three words were never shown, so they are still unbatched.
    let batchStore = BatchStore(dbQueue: dbQueue)
    #expect(try batchStore.unseenWordIndices(level: 2).count == 3)
}

@Test func testMarkingWordsAtTwoLevelsWritesTwoRetiredBatchesEachHoldingOnlyItsOwnLevelsWords() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 20, 2: 20, 3: 20])
    let today = provider(at: date(2026, 1, 5))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)
    let session = try engine.startPlacementTest()

    var level2Known: [Int] = []
    for i in 0..<5 {
        let word = try #require(session.currentWord)
        #expect(word.level == 2)
        let known = i < 1 // one known at level 2 moves down to level 1
        if known { level2Known.append(word.wordIndex) }
        try session.answer(known ? .know : .dontKnow)
    }

    var level1Known: [Int] = []
    for i in 0..<5 {
        let word = try #require(session.currentWord)
        #expect(word.level == 1)
        let known = i < 3 // three known at level 1 stops the walk
        if known { level1Known.append(word.wordIndex) }
        try session.answer(known ? .know : .dontKnow)
    }

    #expect(session.isFinished)
    #expect(session.recommendedLevel == 1)

    let batchRows = try dbQueue.read { db in
        try Row.fetchAll(db, sql: "SELECT id, level, created_on, next_look_on, look_number FROM batch ORDER BY level;")
    }
    #expect(batchRows.count == 2)

    for row in batchRows {
        let level: Int = row["level"]
        let nextLookOn: LocalDate? = row["next_look_on"]
        let lookNumber: Int = row["look_number"]
        let createdOn: LocalDate = row["created_on"]
        #expect(nextLookOn == nil)
        #expect(lookNumber == 2)
        #expect(createdOn == localDate(2026, 1, 5))

        let batchID: Int64 = row["id"]
        let words = try dbQueue.read { db in
            try Int.fetchAll(db, sql: "SELECT word_index FROM batch_word WHERE batch_id = ?;", arguments: [batchID])
        }
        switch level {
        case 1: #expect(Set(words) == Set(level1Known))
        case 2: #expect(Set(words) == Set(level2Known))
        default: Issue.record("unexpected batch level \(level)")
        }
    }
}

@Test func testAMarkedWordNeverReappearsInALaterSessionDrawAndAnUnmarkedOneDoes() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [2: 6])
    let today = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)
    let session = try engine.startPlacementTest()

    var known: [Int] = []
    var dontKnow: [Int] = []
    for i in 0..<5 {
        let word = try #require(session.currentWord)
        let isKnown = i < 3 // three known stops the walk at level 2
        try session.answer(isKnown ? .know : .dontKnow)
        if isKnown { known.append(word.wordIndex) } else { dontKnow.append(word.wordIndex) }
    }
    #expect(session.isFinished)

    let neverDrawn = Set(1...6).subtracting(known).subtracting(dontKnow)
    #expect(neverDrawn.count == 1)

    let laterSession = try engine.startSession(level: 2)
    var drawn: [Int] = []
    while let card = laterSession.currentCard {
        drawn.append(card.word.wordIndex)
        try laterSession.swipe(.right)
    }

    #expect(Set(drawn).isDisjoint(with: Set(known)))
    for wordIndex in dontKnow + Array(neverDrawn) {
        #expect(drawn.contains(wordIndex))
    }
}

@Test func testMarkedWordsDoNotSpendTheDaysEightWordAllowance() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [2: 20])
    let today = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, today: today)
    let session = try engine.startPlacementTest()

    for i in 0..<5 {
        _ = try #require(session.currentWord)
        try session.answer(i < 3 ? .know : .dontKnow) // three known stops the walk
    }
    #expect(session.isFinished)

    let batchStore = BatchStore(dbQueue: dbQueue)
    #expect(try batchStore.hasBatchCreatedToday(today: today) == false)

    let laterSession = try engine.startSession(level: 2)
    #expect(laterSession.drawnCount == 8)
}

@Test func testRunningThePlacementTestASecondTimeAddsMarksAndNeverRepeatsABatchedWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [2: 20])
    let today = provider(at: date(2026, 1, 1))
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, seed: 1, today: today)

    let first = try engine.startPlacementTest()
    var firstSeen: [Int] = []
    var firstKnown: [Int] = []
    for i in 0..<5 {
        let word = try #require(first.currentWord)
        firstSeen.append(word.wordIndex)
        let known = i < 3
        if known { firstKnown.append(word.wordIndex) }
        try first.answer(known ? .know : .dontKnow)
    }
    #expect(first.isFinished)

    let batchCountAfterFirst = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM batch;") }

    let second = try engine.startPlacementTest()
    var secondSeen: [Int] = []
    for i in 0..<5 {
        let word = try #require(second.currentWord)
        #expect(!firstKnown.contains(word.wordIndex), "must never redraw a word already sitting in a batch")
        secondSeen.append(word.wordIndex)
        try second.answer(i < 2 ? .know : .dontKnow)
    }
    #expect(second.isFinished)

    let batchCountAfterSecond = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM batch;") }
    #expect(batchCountAfterSecond! > batchCountAfterFirst!)
    #expect(Set(firstKnown).isDisjoint(with: Set(secondSeen)))

    let batchStore = BatchStore(dbQueue: dbQueue)
    for wordIndex in firstKnown {
        #expect(try batchStore.isIntroduced(wordIndex: wordIndex))
    }
}
