import Foundation
import GRDB
import Testing
@testable import LaoshuKit

/// D5, D6: the `preference` table and the migration that creates it, the
/// `StudyDirection` it stores, and the faces `Card` builds from it.
private func localDate(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

private struct PreferenceRow: Equatable {
    let direction: String
}

private func fetchPreference(_ dbQueue: DatabaseQueue) throws -> PreferenceRow {
    try dbQueue.read { db in
        let row = try Row.fetchOne(db, sql: "SELECT direction FROM preference WHERE id = 1;")!
        return PreferenceRow(direction: row["direction"])
    }
}

@Test func testDirectionIsReceptiveOnAFreshDatabase() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)

    let direction = try PreferenceStore(dbQueue: dbQueue).direction()

    #expect(direction == .receptive)
    #expect(try fetchPreference(dbQueue).direction == "receptive")
}

@Test func testDirectionSurvivesBeingSetClosedAndReadBack() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    let firstOpen = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
    try PreferenceStore(dbQueue: firstOpen).setDirection(.reverse)
    try firstOpen.close()

    let secondOpen = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
    let direction = try PreferenceStore(dbQueue: secondOpen).direction()

    #expect(direction == .reverse)
}

/// D14: this fixture is built on the schema checkpoint 4 actually shipped,
/// not by calling `LaoshuDatabase`'s own migrator and inserting rows
/// afterward.
@Test func testMigrationSeedsReceptiveOnADatabaseBuiltTheWayCheckpoint4Shipped() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint4ReviewLog(
        at: reviewLogURL,
        batches: [(level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: localDate(2026, 1, 2), lookNumber: 0, wordIndices: [1, 2, 3])],
        reviewRows: [(wordIndex: 4, reviewedAt: Date(), grade: .good)],
        placementStatus: "taken",
        placementRecommendedLevel: nil
    )

    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)

    let preference = try fetchPreference(dbQueue)
    #expect(preference.direction == "receptive")

    // The failure with the most to lose here is not a missing preference but
    // a migration that seeds one and drops weeks of study on the way. Assert
    // every row the fixture wrote is still there afterwards.
    try dbQueue.read { db in
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM batch") == 1)
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM batch_word") == 3)
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM review") == 1)
        #expect(try String.fetchOne(db, sql: "SELECT status FROM placement WHERE id = 1") == "taken")
        let batch = try Row.fetchOne(db, sql: "SELECT level, created_on, next_look_on, look_number FROM batch")
        #expect(batch?["level"] == 1)
        #expect(batch?["created_on"] == "2026-01-01")
        #expect(batch?["next_look_on"] == "2026-01-02")
        #expect(batch?["look_number"] == 0)
    }
}

@Test func testPreferenceMigrationNeverRunsTwice() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint4ReviewLog(at: reviewLogURL)

    let firstOpen = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
    try PreferenceStore(dbQueue: firstOpen).setDirection(.reverse)
    try firstOpen.close()

    // A later launch must find the migration already recorded and leave the
    // row alone rather than re-seeding it back to receptive.
    let secondOpen = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
    let preference = try fetchPreference(secondOpen)
    #expect(preference.direction == "reverse")

    let rowCount = try secondOpen.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM preference") }
    #expect(rowCount == 1)
}

@Test func testAMissingPreferenceRowReadsAsReceptive() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    try dbQueue.write { db in
        try db.execute(sql: "DELETE FROM preference;")
    }

    let direction = try PreferenceStore(dbQueue: dbQueue).direction()

    #expect(direction == .receptive)
}

@Test func testASessionDrawnReceptiveGivesEveryCardChinesePromptAndMeaningAnswer() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.direction == .receptive)
    while let card = session.currentCard {
        #expect(card.promptFace == .chinese)
        #expect(card.answerFace == .meaning)
        try session.swipe(.right)
    }
}

@Test func testASessionDrawnReverseGivesEveryCardMeaningPromptAndChineseAnswer() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    try PreferenceStore(dbQueue: dbQueue).setDirection(.reverse)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue)

    let session = try engine.startSession(level: 1)

    #expect(session.direction == .reverse)
    while let card = session.currentCard {
        #expect(card.promptFace == .meaning)
        #expect(card.answerFace == .chinese)
        try session.swipe(.right)
    }
}

private struct ReviewRow: Equatable {
    let wordIndex: Int
    let grade: String
}

private struct BatchRow: Equatable {
    let level: Int
    let createdOn: String
    let nextLookOn: String?
    let lookNumber: Int
}

private struct BatchWordRow: Equatable {
    let batchId: Int64
    let wordIndex: Int
}

private func fetchReviewRows(_ dbQueue: DatabaseQueue) throws -> [ReviewRow] {
    try dbQueue.read { db in
        try Row.fetchAll(db, sql: "SELECT word_index, grade FROM review ORDER BY rowid;").map {
            ReviewRow(wordIndex: $0["word_index"], grade: $0["grade"])
        }
    }
}

private func fetchBatchRows(_ dbQueue: DatabaseQueue) throws -> [BatchRow] {
    try dbQueue.read { db in
        try Row.fetchAll(db, sql: "SELECT level, created_on, next_look_on, look_number FROM batch ORDER BY id;").map {
            BatchRow(level: $0["level"], createdOn: $0["created_on"], nextLookOn: $0["next_look_on"], lookNumber: $0["look_number"])
        }
    }
}

private func fetchBatchWordRows(_ dbQueue: DatabaseQueue) throws -> [BatchWordRow] {
    try dbQueue.read { db in
        try Row.fetchAll(db, sql: "SELECT batch_id, word_index FROM batch_word ORDER BY batch_id, word_index;").map {
            BatchWordRow(batchId: $0["batch_id"], wordIndex: $0["word_index"])
        }
    }
}

/// Runs the same scripted session against a fresh database, direction set
/// beforehand: swipe left on the first three draws (each requeues once),
/// swipe right on everything after — a script chosen by draw position only,
/// never by a card's face, so it plays out identically in both directions.
private func runScriptedSession(direction: StudyDirection, seed: UInt64) throws -> DatabaseQueue {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 20)
    try PreferenceStore(dbQueue: dbQueue).setDirection(direction)
    let engine = TestFixtures.makeEngine(dbQueue: dbQueue, seed: seed)

    let session = try engine.startSession(level: 1)
    var totalSwipes = 0
    while session.currentCard != nil {
        let swipeDirection: SwipeDirection = totalSwipes < 3 ? .left : .right
        try session.swipe(swipeDirection)
        totalSwipes += 1
    }

    return dbQueue
}

@Test func testTheSameScriptedSessionProducesIdenticalRowsInBothDirections() throws {
    let receptiveQueue = try runScriptedSession(direction: .receptive, seed: 42)
    let reverseQueue = try runScriptedSession(direction: .reverse, seed: 42)

    #expect(try fetchReviewRows(receptiveQueue) == fetchReviewRows(reverseQueue))
    #expect(try fetchBatchRows(receptiveQueue) == fetchBatchRows(reverseQueue))
    #expect(try fetchBatchWordRows(receptiveQueue) == fetchBatchWordRows(reverseQueue))
}

// MARK: - D9, D10, D11: the two settings on the `preference` row

/// D24a: this fixture is built on the schema checkpoint 11 actually shipped,
/// not by calling `LaoshuDatabase`'s own migrator and inserting rows
/// afterward.
@Test func testMigrationAddsSettingsToADatabaseBuiltTheWayCheckpoint11Shipped() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint11ReviewLog(
        at: reviewLogURL,
        batches: [(level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: localDate(2026, 1, 2), lookNumber: 0, wordIndices: [1, 2, 3])],
        reviewRows: [(wordIndex: 4, reviewedAt: Date(), grade: .good)],
        placementStatus: "taken",
        placementRecommendedLevel: nil,
        direction: "reverse"
    )

    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)

    let preferences = try PreferenceStore(dbQueue: dbQueue).preferences()
    #expect(preferences.direction == .reverse)
    #expect(preferences.newWordsPerDay == 8)
    #expect(preferences.speakOnFlip == true)

    // The failure with the most to lose here is not a missing setting but a
    // migration that adds one and drops weeks of study on the way.
    try dbQueue.read { db in
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM batch") == 1)
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM batch_word") == 3)
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM review") == 1)
        #expect(try String.fetchOne(db, sql: "SELECT status FROM placement WHERE id = 1") == "taken")
        let batch = try Row.fetchOne(db, sql: "SELECT level, created_on, next_look_on, look_number FROM batch")
        #expect(batch?["level"] == 1)
        #expect(batch?["created_on"] == "2026-01-01")
        #expect(batch?["next_look_on"] == "2026-01-02")
        #expect(batch?["look_number"] == 0)
    }
}

@Test func testNewWordsPerDayCheckConstraintRejectsOutOfRangeValues() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)

    #expect(throws: (any Error).self) {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE preference SET new_words_per_day = 3 WHERE id = 1;")
        }
    }
    #expect(throws: (any Error).self) {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE preference SET new_words_per_day = 21 WHERE id = 1;")
        }
    }
}

@Test func testSpeakOnFlipCheckConstraintRejectsValuesOtherThanZeroOrOne() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)

    #expect(throws: (any Error).self) {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE preference SET speak_on_flip = 2 WHERE id = 1;")
        }
    }
}

@Test func testPreferencesReadsDefaultsOnAFreshDatabase() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)

    let preferences = try PreferenceStore(dbQueue: dbQueue).preferences()

    #expect(preferences == Preferences(direction: .receptive, newWordsPerDay: 8, speakOnFlip: true))
}

@Test func testEachSettingWriterRoundTrips() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    let store = PreferenceStore(dbQueue: dbQueue)

    try store.setNewWordsPerDay(12)
    try store.setSpeakOnFlip(false)

    let preferences = try store.preferences()
    #expect(preferences.newWordsPerDay == 12)
    #expect(preferences.speakOnFlip == false)
}

@Test func testAMissingPreferenceRowReadsAsTheDefaultsForTheWholeRow() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)
    try dbQueue.write { db in
        try db.execute(sql: "DELETE FROM preference;")
    }

    let preferences = try PreferenceStore(dbQueue: dbQueue).preferences()

    #expect(preferences == Preferences(direction: .receptive, newWordsPerDay: 8, speakOnFlip: true))
}
