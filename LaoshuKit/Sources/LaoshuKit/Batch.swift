import Foundation

/// A day's words moving together along the ladder that brings them back
/// (D2): introduced, looked at the next day, looked at again seven days
/// after that look, retired. `nextLookOn` is `nil` exactly when the batch
/// has retired.
public struct Batch: Sendable, Equatable {
    public var id: Int64?
    public let level: Int
    public let createdOn: LocalDate
    public private(set) var nextLookOn: LocalDate?
    public private(set) var lookNumber: Int

    public init(id: Int64? = nil, level: Int, createdOn: LocalDate, nextLookOn: LocalDate?, lookNumber: Int) {
        self.id = id
        self.level = level
        self.createdOn = createdOn
        self.nextLookOn = nextLookOn
        self.lookNumber = lookNumber
    }

    public var isRetired: Bool { nextLookOn == nil }

    /// Whether this batch is up on `today` — due once, not before, and never
    /// again once it has retired.
    public func isDue(on today: LocalDate) -> Bool {
        guard let nextLookOn else { return false }
        return nextLookOn <= today
    }

    /// Advances the ladder after a look actually taken on `today` (D2). D4:
    /// the second look is anchored to when the first was actually taken, not
    /// to a date computed at creation, so a late first look pushes the
    /// second one out with it. The ladder retires after the second look.
    public func lookTaken(on today: LocalDate) -> Batch {
        precondition(!isRetired, "cannot take a look on a retired batch")
        var next = self
        next.lookNumber += 1
        next.nextLookOn = next.lookNumber >= 2 ? nil : today.addingDays(7)
        return next
    }
}

/// Builds a freshly introduced batch (D2, D4a).
public enum BatchScheduler {
    public static func createBatch(level: Int, today: TodayProvider) -> Batch {
        let createdOn = today.today()

        // D4a: the first look is never earlier than the day after the raw
        // wall-clock day the batch was created, even when the business day
        // (04:00 boundary) would otherwise put `createdOn` a day earlier for
        // a session run before 04:00.
        let earliestFirstLook = today.wallClockToday().addingDays(1)
        let firstLookOn = max(createdOn.addingDays(1), earliestFirstLook)

        return Batch(level: level, createdOn: createdOn, nextLookOn: firstLookOn, lookNumber: 0)
    }
}
