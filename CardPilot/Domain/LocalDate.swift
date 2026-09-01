import Foundation

enum LocalDateError: Error, Equatable {
    case invalidRawValue(Int)
    case invalidComponents(year: Int, month: Int, day: Int)
    case invalidMonthKey(Int)
    case calendarConversionFailed
}

/// A calendar date with no time zone or time-of-day semantics.
struct LocalDate: Codable, Comparable, Hashable, Identifiable, Sendable, CustomStringConvertible {
    let rawValue: Int

    var id: Int { rawValue }
    var year: Int { rawValue / 10_000 }
    var month: Int { (rawValue / 100) % 100 }
    var day: Int { rawValue % 100 }
    var monthKey: Int { year * 100 + month }
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init(rawValue: Int) throws {
        let year = rawValue / 10_000
        let month = (rawValue / 100) % 100
        let day = rawValue % 100
        guard Self.isValid(year: year, month: month, day: day) else {
            throw LocalDateError.invalidRawValue(rawValue)
        }
        self.rawValue = rawValue
    }

    init(year: Int, month: Int, day: Int) throws {
        guard Self.isValid(year: year, month: month, day: day) else {
            throw LocalDateError.invalidComponents(year: year, month: month, day: day)
        }
        self.rawValue = year * 10_000 + month * 100 + day
    }

    init(date: Date, timeZone: TimeZone) {
        let calendar = Self.calendar(timeZone: timeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = (components.year ?? 1) * 10_000
            + (components.month ?? 1) * 100
            + (components.day ?? 1)
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func isValid(year: Int, month: Int, day: Int, timeZone: TimeZone = .current) -> Bool {
        guard (1...9_999).contains(year), (1...12).contains(month) else { return false }
        return (1...daysInMonth(year: year, month: month, timeZone: timeZone)).contains(day)
    }

    static func isValidMonthKey(_ monthKey: Int) -> Bool {
        let year = monthKey / 100
        let month = monthKey % 100
        return (1...9_999).contains(year) && (1...12).contains(month)
    }

    /// Returns inclusive, ascending month keys. Invalid or reversed ranges are empty.
    static func monthKeys(from startMonthKey: Int, through endMonthKey: Int) -> [Int] {
        guard isValidMonthKey(startMonthKey), isValidMonthKey(endMonthKey), startMonthKey <= endMonthKey else {
            return []
        }
        let startIndex = (startMonthKey / 100) * 12 + startMonthKey % 100 - 1
        let endIndex = (endMonthKey / 100) * 12 + endMonthKey % 100 - 1
        return (startIndex...endIndex).map { index in
            (index / 12) * 100 + index % 12 + 1
        }
    }

    static func daysInMonth(year: Int, month: Int, timeZone: TimeZone = .current) -> Int {
        guard (1...9_999).contains(year), (1...12).contains(month) else { return 0 }
        let calendar = Self.calendar(timeZone: timeZone)
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 0 }
        return range.count
    }

    static func firstDay(ofMonthKey monthKey: Int) throws -> LocalDate {
        guard isValidMonthKey(monthKey) else { throw LocalDateError.invalidMonthKey(monthKey) }
        return try LocalDate(year: monthKey / 100, month: monthKey % 100, day: 1)
    }

    func date(in timeZone: TimeZone = .current) -> Date {
        let calendar = Self.calendar(timeZone: timeZone)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            preconditionFailure("A valid LocalDate must convert to a Date")
        }
        return calendar.startOfDay(for: date)
    }

    func addingDays(_ value: Int, timeZone: TimeZone = .current) -> LocalDate {
        let calendar = Self.calendar(timeZone: timeZone)
        guard let result = calendar.date(byAdding: .day, value: value, to: date(in: timeZone)) else {
            preconditionFailure("Calendar could not add days to a valid LocalDate")
        }
        return LocalDate(date: result, timeZone: timeZone)
    }

    func addingMonths(_ value: Int, timeZone: TimeZone = .current) -> LocalDate {
        let calendar = Self.calendar(timeZone: timeZone)
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let shifted = calendar.date(byAdding: .month, value: value, to: firstOfMonth) else {
            preconditionFailure("Calendar could not add months to a valid LocalDate")
        }
        let components = calendar.dateComponents([.year, .month], from: shifted)
        let shiftedYear = components.year ?? year
        let shiftedMonth = components.month ?? month
        let shiftedDay = min(day, Self.daysInMonth(year: shiftedYear, month: shiftedMonth, timeZone: timeZone))
        return try! LocalDate(year: shiftedYear, month: shiftedMonth, day: shiftedDay)
    }

    /// Month arithmetic that returns nil when the requested result is outside the supported year range.
    func addingMonthsIfPossible(_ value: Int, timeZone: TimeZone = .current) -> LocalDate? {
        let calendar = Self.calendar(timeZone: timeZone)
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let shifted = calendar.date(byAdding: .month, value: value, to: firstOfMonth) else {
            return nil
        }
        let components = calendar.dateComponents([.year, .month], from: shifted)
        guard let shiftedYear = components.year,
              let shiftedMonth = components.month,
              Self.isValid(year: shiftedYear, month: shiftedMonth, day: 1, timeZone: timeZone) else {
            return nil
        }
        let shiftedDay = min(day, Self.daysInMonth(year: shiftedYear, month: shiftedMonth, timeZone: timeZone))
        return try? LocalDate(year: shiftedYear, month: shiftedMonth, day: shiftedDay)
    }
}
