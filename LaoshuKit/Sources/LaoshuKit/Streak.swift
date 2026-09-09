import Foundation
import GRDB

/// The state shown beside the streak's number, one of four (D6): where the
/// user stands relative to today, not just whether the run is alive.
public enum StreakState: Sendable, Equatable {
    case studiedToday
    case notYetToday
    case restDayUsed
    case none
}

/// How many days in a row the user has studied, and what to say about today
/// (D6).
public struct Streak: Sendable, Equatable {
    public let days: Int
    public let state: StreakState

    public init(days: Int, state: StreakState) {
        self.days = days
        self.state = state
    }
}

/// Reads `Streak` from the review log, deriving it fresh on every call
/// rather than storing it (D7, D9). Nothing here writes anything.
public struct StreakReader: Sendable {
    private let dbQueue: DatabaseQueue
    private let today: TodayProvider

    public init(dbQueue: DatabaseQueue, today: TodayProvider) {
        self.dbQueue = dbQueue
        self.today = today
    }

    /// One full scan of `review`, grouping every row into its business day
    /// with no early stop and no new index (D7), then applying D4's rule.
    public func read() throws -> Streak {
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT reviewed_at FROM review;")
        }

        let studiedDays = Set(rows.map { row -> LocalDate in
            let reviewedAt: Double = row["reviewed_at"]
            return today.businessDay(for: Date(timeIntervalSince1970: reviewedAt))
        })

        let now = today.today()
        let sorted = studiedDays.filter { $0 <= now }.sorted(by: >)

        guard let head = sorted.first else {
            return Streak(days: 0, state: .none)
        }

        let headGap = now.daysSince(head)
        guard headGap < 3 else {
            return Streak(days: 0, state: .none)
        }

        let state: StreakState
        switch headGap {
        case 0: state = .studiedToday
        case 1: state = .notYetToday
        default: state = .restDayUsed
        }

        var lastForgiven: LocalDate?
        func canForgive(_ m: LocalDate) -> Bool {
            guard let last = lastForgiven else { return true }
            return last.daysSince(m) >= 7
        }

        if headGap == 2 {
            let m = now.addingDays(-1)
            lastForgiven = m
        }

        var days = 1
        var index = 1
        while index < sorted.count {
            let gap = sorted[index - 1].daysSince(sorted[index])
            if gap == 1 {
                days += 1
                index += 1
                continue
            } else if gap == 2 {
                let m = sorted[index - 1].addingDays(-1)
                guard canForgive(m) else { break }
                lastForgiven = m
                days += 1
                index += 1
                continue
            } else {
                break
            }
        }

        return Streak(days: days, state: state)
    }
}
