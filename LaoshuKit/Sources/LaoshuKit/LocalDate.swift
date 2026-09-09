import Foundation
import GRDB

/// A calendar date with no time component, stored everywhere as
/// `YYYY-MM-DD` (D9) rather than a timestamp — a batch's schedule is about
/// which day it is due, not what instant that is.
public struct LocalDate: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. Fails on anything else, including a timestamp.
    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Pure calendar-day arithmetic, done against a fixed UTC calendar so DST
    /// transitions in whatever timezone a caller lives in can never make
    /// "seven days later" land on the wrong date.
    private static let arithmeticCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public func addingDays(_ days: Int) -> LocalDate {
        let calendar = Self.arithmeticCalendar
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let shifted = calendar.date(byAdding: .day, value: days, to: date)!
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return LocalDate(year: components.year!, month: components.month!, day: components.day!)
    }

    /// How many whole days after `other` this date falls — negative if it
    /// falls before. Used by replay to tell how far behind schedule an
    /// overdue look is.
    public func daysSince(_ other: LocalDate) -> Int {
        let calendar = Self.arithmeticCalendar
        let otherDate = calendar.date(from: DateComponents(year: other.year, month: other.month, day: other.day))!
        let selfDate = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.dateComponents([.day], from: otherDate, to: selfDate).day!
    }

    /// The plain calendar date `date` falls on in `calendar`'s timezone, with
    /// no day-boundary adjustment — the raw wall-clock day (D4a).
    public static func calendarDay(for date: Date, calendar: Calendar) -> LocalDate {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: components.year!, month: components.month!, day: components.day!)
    }

    /// The day `date` falls in once the day is taken to begin at
    /// `dayStartHour` local time rather than midnight (D9's 04:00 boundary).
    public static func businessDay(for date: Date, calendar: Calendar, dayStartHour: Int = 4) -> LocalDate {
        let shifted = calendar.date(byAdding: .hour, value: -dayStartHour, to: date)!
        return calendarDay(for: shifted, calendar: calendar)
    }
}

extension LocalDate: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        description.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> LocalDate? {
        guard case .string(let string) = dbValue.storage else { return nil }
        return LocalDate(string: string)
    }
}
