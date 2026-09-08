import Foundation

/// The one seam the batch ladder reads the clock through (D21). An
/// eight-day ladder has to be testable in a single run, so nothing in
/// `Batch` or `BatchScheduler` calls `Date()` directly — everything asks a
/// `TodayProvider` instead, and a test hands it a fixed clock.
public struct TodayProvider: Sendable {
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    public init(calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.clock = clock
    }

    /// The business day right now: the local calendar date once the day is
    /// taken to begin at 04:00 rather than midnight (D9).
    public func today() -> LocalDate {
        LocalDate.businessDay(for: clock(), calendar: calendar)
    }

    /// The plain wall-clock calendar date right now, with no 04:00 shift.
    /// D4a floors a batch's first look against this raw day, which is what
    /// stops a session just after midnight — still "yesterday" as a business
    /// day — from putting the first look later that same wall-clock morning.
    public func wallClockToday() -> LocalDate {
        LocalDate.calendarDay(for: clock(), calendar: calendar)
    }
}
