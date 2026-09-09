import Foundation
import GRDB

/// Which way a study session asks: the pinyin/hanzi side asking and the
/// meaning answering, or the other way around (D5, D6).
public enum StudyDirection: String, Sendable, Equatable {
    case receptive
    case reverse
}

/// Reads and writes the singleton `preference` row: the study direction
/// every new session draws with.
public struct PreferenceStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func direction() throws -> StudyDirection {
        try dbQueue.read { db in
            // No row at all should be unreachable, since the migration
            // writes one. Read as receptive rather than trapping, the way
            // `PlacementStore.status()` reads a missing row as not taken.
            guard let row = try Row.fetchOne(
                db, sql: "SELECT direction FROM preference WHERE id = 1;"
            ) else { return .receptive }
            let direction: String = row["direction"]
            return StudyDirection(rawValue: direction) ?? .receptive
        }
    }

    public func setDirection(_ direction: StudyDirection) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE preference SET direction = ? WHERE id = 1;",
                arguments: [direction.rawValue]
            )
        }
    }
}
