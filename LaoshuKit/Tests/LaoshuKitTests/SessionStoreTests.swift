import Foundation
import GRDB
import Testing
@testable import LaoshuKit

/// D26-D29: the `session` and `session_card` tables, the migration that
/// creates them, and `SessionStore`, the only thing that queries them.
private func localDate(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

private func makeSession(
    level: Int = 1,
    status: SessionStatus = .live,
    cards: [StoredSessionCard]
) -> StoredSession {
    StoredSession(
        level: level,
        createdOn: localDate(2026, 1, 1),
        direction: .receptive,
        speakOnFlip: true,
        status: status,
        cards: cards
    )
}

@Test func testInsertSessionWritesTheSessionAndItsCardsInOnePlace() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    let session = makeSession(cards: [
        StoredSessionCard(wordIndex: 1, position: 0),
        StoredSessionCard(wordIndex: 2, position: 1),
    ])

    let created = try store.insertSession(session)

    #expect(created.id != nil)
    let cardCount = try dbQueue.read { db in
        try Int.fetchOne(db, sql: "SELECT count(*) FROM session_card WHERE session_id = ?;", arguments: [created.id])
    }
    #expect(cardCount == 2)
}

@Test func testLiveSessionReadsALevelsLiveSessionWithItsCardsInPositionOrder() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    let created = try store.insertSession(makeSession(cards: [
        StoredSessionCard(wordIndex: 3, position: 2),
        StoredSessionCard(wordIndex: 1, position: 0),
        StoredSessionCard(wordIndex: 2, position: 1),
    ]))

    let read = try store.liveSession(level: 1)

    #expect(read?.id == created.id)
    #expect(read?.cards.map(\.wordIndex) == [1, 2, 3])
}

@Test func testLiveSessionReadsNilWhenTheLevelHoldsNoLiveSession() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)

    #expect(try store.liveSession(level: 1) == nil)
}

@Test func testSettleCardClearsPositionAndAssignsSettledOrderStartingAtZero() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    let created = try store.insertSession(makeSession(cards: [
        StoredSessionCard(wordIndex: 1, position: 0),
        StoredSessionCard(wordIndex: 2, position: 1),
    ]))

    try store.settleCard(sessionID: created.id!, wordIndex: 1, outcome: .finished)
    try store.settleCard(sessionID: created.id!, wordIndex: 2, outcome: .parked)

    let session = try store.liveSession(level: 1)!
    let first = session.cards.first { $0.wordIndex == 1 }!
    let second = session.cards.first { $0.wordIndex == 2 }!
    #expect(first.position == nil)
    #expect(first.outcome == .finished)
    #expect(first.settledOrder == 0)
    #expect(second.settledOrder == 1)
}

@Test func testRewritePendingPositionsReordersTheQueueWithoutTrippingTheUniqueIndex() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    let created = try store.insertSession(makeSession(cards: [
        StoredSessionCard(wordIndex: 1, position: 0),
        StoredSessionCard(wordIndex: 2, position: 1),
        StoredSessionCard(wordIndex: 3, position: 2),
    ]))

    // Card 3 moves to the front, swapping into a position another pending
    // card already holds — exactly what a naive in-place update would trip
    // the partial unique index on.
    try store.rewritePendingPositions(sessionID: created.id!, order: [3, 1, 2])

    let session = try store.liveSession(level: 1)!
    #expect(session.cards.map(\.wordIndex) == [3, 1, 2])
    #expect(session.cards.map(\.position) == [0, 1, 2])
}

@Test func testSetStatusChangesOnlyTheNamedSession() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    let created = try store.insertSession(makeSession(cards: [StoredSessionCard(wordIndex: 1, position: 0)]))

    try store.setStatus(sessionID: created.id!, status: .done)

    #expect(try store.liveSession(level: 1) == nil)
    let status = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT status FROM session WHERE id = ?;", arguments: [created.id])
    }
    #expect(status == "done")
}

@Test func testASecondLiveSessionOnTheSameLevelIsRefusedByTheDatabase() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)
    try store.insertSession(makeSession(cards: [StoredSessionCard(wordIndex: 1, position: 0)]))

    #expect(throws: (any Error).self) {
        try store.insertSession(makeSession(cards: [StoredSessionCard(wordIndex: 2, position: 0)]))
    }
}

@Test func testASecondLiveSessionOnADifferentLevelIsAllowed() throws {
    let dbQueue = try TestFixtures.makeDatabase(levelCounts: [1: 8, 2: 8])
    let store = SessionStore(dbQueue: dbQueue)
    try store.insertSession(makeSession(level: 1, cards: [StoredSessionCard(wordIndex: 1, position: 0)]))

    try store.insertSession(makeSession(level: 2, cards: [StoredSessionCard(wordIndex: 9, position: 0)]))

    #expect(try store.liveSession(level: 1) != nil)
    #expect(try store.liveSession(level: 2) != nil)
}

@Test func testTwoCardsOfOneSessionCannotHoldTheSamePosition() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = SessionStore(dbQueue: dbQueue)

    #expect(throws: (any Error).self) {
        try store.insertSession(makeSession(cards: [
            StoredSessionCard(wordIndex: 1, position: 0),
            StoredSessionCard(wordIndex: 2, position: 0),
        ]))
    }
}

/// D27: this fixture is built on the schema checkpoint 6 actually shipped,
/// not by calling `LaoshuDatabase`'s own migrator and inserting rows
/// afterward — the same reasoning `testMigrationAddsSettingsToADatabaseBuiltTheWayCheckpoint11Shipped`
/// already applies one migration back.
@Test func testResumeReadsADatabaseWrittenByThePreviousVersion() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint6ReviewLog(
        at: reviewLogURL,
        batches: [(level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: localDate(2026, 1, 2), lookNumber: 0, wordIndices: [1, 2, 3])],
        reviewRows: [(wordIndex: 4, reviewedAt: Date(), grade: .good)],
        placementStatus: "taken",
        placementRecommendedLevel: nil,
        direction: "reverse",
        newWordsPerDay: 12,
        speakOnFlip: false
    )

    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)

    // The migration itself must succeed and leave every row the previous
    // version wrote intact — the failure with the most to lose is not a
    // missing table but a migration that adds one and drops weeks of study
    // on the way.
    let batchCount = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM batch") }
    let batchWordCount = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM batch_word") }
    let reviewCount = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM review") }
    let placementStatus = try dbQueue.read { db in try String.fetchOne(db, sql: "SELECT status FROM placement WHERE id = 1") }
    let preferenceDirection = try dbQueue.read { db in try String.fetchOne(db, sql: "SELECT direction FROM preference WHERE id = 1") }
    let newWordsPerDay = try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT new_words_per_day FROM preference WHERE id = 1") }
    #expect(batchCount == 1)
    #expect(batchWordCount == 3)
    #expect(reviewCount == 1)
    #expect(placementStatus == "taken")
    #expect(preferenceDirection == "reverse")
    #expect(newWordsPerDay == 12)

    // The new tables are usable through the store the same launch.
    let store = SessionStore(dbQueue: dbQueue)
    try store.insertSession(makeSession(cards: [StoredSessionCard(wordIndex: 5, position: 0)]))
    #expect(try store.liveSession(level: 1) != nil)
}
