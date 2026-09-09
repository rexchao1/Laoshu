import Foundation
import GRDB
import Testing
@testable import LaoshuKit

/// D13/D13a: the `placement` table and the migration that creates it,
/// seeded so the first-run gate it backs never fires for a phone that
/// already holds weeks of study (D14).
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

private struct PlacementRow: Equatable {
    let status: String
    let recommendedLevel: Int?
}

private func fetchPlacement(_ dbQueue: DatabaseQueue) throws -> PlacementRow {
    try dbQueue.read { db in
        let row = try Row.fetchOne(db, sql: "SELECT status, recommended_level FROM placement WHERE id = 1;")!
        return PlacementRow(status: row["status"], recommendedLevel: row["recommended_level"])
    }
}

/// D14: this fixture is built on the schema checkpoint 2 actually shipped,
/// not by calling `LaoshuDatabase`'s own migrator and inserting rows
/// afterward — the exact defect that shipped in checkpoint 2 (commit
/// 6b1b765), where a fixture built by the migrator under test proved
/// nothing about upgrades.
@Test func testMigrationSeedsPlacementAsAlreadyTakenOnADatabaseWithStudyInIt() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint2ReviewLog(
        at: reviewLogURL,
        batches: [(level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: localDate(2026, 1, 2), lookNumber: 0, wordIndices: [1, 2, 3])],
        reviewRows: [(wordIndex: 4, reviewedAt: date(2026, 1, 1), grade: .good)]
    )

    let today = provider(at: date(2026, 1, 3))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)

    let placement = try fetchPlacement(dbQueue)
    #expect(placement.status == "taken")
    #expect(placement.recommendedLevel == nil)
}

/// A review row alone, with no batch, must also count as already studied.
@Test func testMigrationSeedsPlacementAsAlreadyTakenWhenOnlyAReviewRowExists() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint2ReviewLog(
        at: reviewLogURL,
        reviewRows: [(wordIndex: 1, reviewedAt: date(2026, 1, 1), grade: .good)]
    )

    let today = provider(at: date(2026, 1, 2))
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)

    let placement = try fetchPlacement(dbQueue)
    #expect(placement.status == "taken")
    #expect(placement.recommendedLevel == nil)
}

@Test func testMigrationLeavesPlacementNotTakenOnAnEmptyDatabase() throws {
    let dbQueue = try TestFixtures.makeDatabase(wordCount: 8)

    let placement = try fetchPlacement(dbQueue)
    #expect(placement.status == "not_taken")
    #expect(placement.recommendedLevel == nil)
}

@Test func testPlacementMigrationNeverRunsTwice() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 8])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")

    try TestFixtures.makeCheckpoint2ReviewLog(
        at: reviewLogURL,
        batches: [(level: 1, createdOn: localDate(2026, 1, 1), nextLookOn: localDate(2026, 1, 2), lookNumber: 0, wordIndices: [1])]
    )

    let today = provider(at: date(2026, 1, 3))

    let firstOpen = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)
    let afterFirstLaunch = try fetchPlacement(firstOpen)
    #expect(afterFirstLaunch.status == "taken")

    // A later launch must find the migration already recorded and leave
    // the seeded row alone rather than trying to insert a second one,
    // which would violate the singleton primary key.
    let secondOpen = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL, today: today)
    let afterSecondLaunch = try fetchPlacement(secondOpen)
    #expect(afterSecondLaunch == afterFirstLaunch)

    let rowCount = try secondOpen.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM placement") }
    #expect(rowCount == 1)
}

/// The PRD's rule that a declined test carries no recommended level lives in
/// the schema rather than in a comment, so the writer that arrives in a later
/// task cannot quietly break it.
@Test func testPlacementRowsThatContradictThemselvesAreRefused() throws {
    let (directory, catalogueURL) = try TestFixtures.makeCatalogue(levelCounts: [1: 5])
    let reviewLogURL = directory.appendingPathComponent("review.sqlite")
    let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)

    #expect(throws: (any Error).self) {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE placement SET status = 'declined', recommended_level = 3;")
        }
    }
    #expect(throws: (any Error).self) {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE placement SET status = 'whatever';")
        }
    }

    // The legitimate write still works.
    try dbQueue.write { db in
        try db.execute(sql: "UPDATE placement SET status = 'taken', recommended_level = 3;")
    }
}
