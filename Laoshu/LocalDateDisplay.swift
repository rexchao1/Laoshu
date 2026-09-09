import Foundation
import LaoshuKit

extension LocalDate {
    /// How this date reads to a person: "tomorrow" rather than "2026-01-02".
    ///
    /// The stored form is D9's `YYYY-MM-DD`, which is a storage format and
    /// not user copy. "Today" is read on the same 04:00 boundary the
    /// scheduler used to produce the date, so the wording can never
    /// disagree with the schedule it describes.
    var friendlyReturnPhrase: String {
        let today = LocalDate.businessDay(for: Date(), calendar: .current)
        if self <= today { return "later today" }
        if self == today.addingDays(1) { return "tomorrow" }
        return "on \(spelledOut)"
    }

    /// The date written out, e.g. "Friday 2 January". Formatted in UTC to
    /// match the UTC calendar `LocalDate` does its arithmetic in, so the
    /// day named is the day stored whatever timezone the phone is in.
    private var spelledOut: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else { return description }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }
}
