import Testing
import GRDB
@testable import LaoshuKit

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
    #expect(try engine.reviewLog.isIntroduced(wordIndex: first))
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

@Test func testSecondSessionDrawsNextEight() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let first = try engine.startSession(level: 1)
    var firstSeen: Set<Int> = []
    while let card = first.currentCard {
        firstSeen.insert(card.word.wordIndex)
        try first.swipe(.right)
    }

    let second = try engine.startSession(level: 1)
    var seen: [Int] = []
    while let card = second.currentCard {
        seen.append(card.word.wordIndex)
        try second.swipe(.right)
    }

    // Randomised or not, a word already reviewed never comes back as new.
    #expect(seen.count == 8)
    #expect(Set(seen).isDisjoint(with: firstSeen))
    #expect(seen.allSatisfy { (1...20).contains($0) })
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
