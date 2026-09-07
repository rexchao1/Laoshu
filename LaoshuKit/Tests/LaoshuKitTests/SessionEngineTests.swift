import Testing
@testable import LaoshuKit

@Test func testSessionDrawsEightLowestUnseen() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let engine = SessionEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 8)
    var seen: [Int] = []
    while let card = session.currentCard {
        seen.append(card.word.wordIndex)
        try session.swipe(.right)
    }
    #expect(seen == [1, 2, 3, 4, 5, 6, 7, 8])
}

@Test func testRightSwipeFinishesWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = SessionEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    let firstWordIndex = session.currentCard?.word.wordIndex
    #expect(firstWordIndex == 1)

    try session.swipe(.right)

    #expect(session.finishedCount == 1)
    #expect(session.currentCard?.word.wordIndex == 2)
    #expect(try engine.reviewLog.isIntroduced(wordIndex: 1))
}

@Test func testLeftSwipeRequeuesAtLeastThreeCardsLater() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = SessionEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    #expect(session.currentCard?.word.wordIndex == 1)
    try session.swipe(.left)

    // Three other cards must be shown before word_index 1 comes back.
    #expect(session.currentCard?.word.wordIndex == 2)
    try session.swipe(.right)
    #expect(session.currentCard?.word.wordIndex == 3)
    try session.swipe(.right)
    #expect(session.currentCard?.word.wordIndex == 4)
    try session.swipe(.right)

    #expect(session.currentCard?.word.wordIndex == 1)
}

@Test func testThirdLeftSwipeParksWord() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 1)
    let engine = SessionEngine(dbQueue: dbQueue)
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

@Test func testSecondSessionDrawsNextEight() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let engine = SessionEngine(dbQueue: dbQueue)

    let first = try engine.startSession(level: 1)
    while !first.isFinished {
        try first.swipe(.right)
    }

    let second = try engine.startSession(level: 1)
    var seen: [Int] = []
    while let card = second.currentCard {
        seen.append(card.word.wordIndex)
        try second.swipe(.right)
    }

    #expect(seen == [9, 10, 11, 12, 13, 14, 15, 16])
}

@Test func testShortLevelEndsEarlyAndReportsCount() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 5)
    let engine = SessionEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.drawnCount == 5)
    var seen: [Int] = []
    while let card = session.currentCard {
        seen.append(card.word.wordIndex)
        try session.swipe(.right)
    }
    #expect(seen == [1, 2, 3, 4, 5])
}

@Test func testLevelSummariesReportsPerLevelCounts() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 3, 2: 2, 3: 5])
    let engine = SessionEngine(dbQueue: dbQueue)

    let summaries = try engine.levelSummaries()

    #expect(summaries == [
        LevelSummary(level: 1, wordCount: 3),
        LevelSummary(level: 2, wordCount: 2),
        LevelSummary(level: 3, wordCount: 5),
    ])
}

@Test func testFirstAttemptRightCountOnlyCountsCleanSwipes() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 3)
    let engine = SessionEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    try session.swipe(.right) // word 1: right first try
    try session.swipe(.left)  // word 2: goes left once
    try session.swipe(.right) // word 3: right first try
    try session.swipe(.right) // word 2 comes back, now right after a left

    #expect(session.finishedCount == 3)
    #expect(session.firstAttemptRightCount == 2)
}

@Test func testParkedWordsRecordsTheWordThatParked() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 1)
    let engine = SessionEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    try session.swipe(.left)
    try session.swipe(.left)
    try session.swipe(.left)

    #expect(session.parkedWords.map(\.wordIndex) == [1])
}

@Test func testRequeuedCardIsPresentedFrontSide() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = SessionEngine(dbQueue: dbQueue)
    let session = try engine.startSession(level: 1)

    session.flipCurrentCard()
    #expect(session.currentCard?.isFlipped == true)

    try session.swipe(.left)

    // word_index 1 reappears after three other cards.
    try session.swipe(.right) // word 2
    try session.swipe(.right) // word 3
    try session.swipe(.right) // word 4

    #expect(session.currentCard?.word.wordIndex == 1)
    #expect(session.currentCard?.isFlipped == false)
}
