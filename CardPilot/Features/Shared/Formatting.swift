import Foundation
import SwiftUI

// Raw-value domain enums are used directly as SwiftUI Picker selections.
extension CreditCardAccountStatus: Hashable {}
extension RepaymentRuleKind: Hashable {}
extension CardStatus: Hashable {}
extension EnrollmentStatus: Hashable {}
extension QualificationDateBasis: Hashable {}
extension TransactionKind: Hashable {}
extension TransactionStatus: Hashable {}

enum CardPilotUI {
    static let maximumReminderOffset = 365

    struct ReminderTime: Equatable {
        let hour: Int
        let minute: Int
    }

    static var homeTimeZone: TimeZone {
        let identifier = UserDefaults.standard.string(forKey: "cardPilot.homeTimeZone")
        return identifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    static func localDate(from date: Date) -> LocalDate {
        LocalDate(date: date, timeZone: homeTimeZone)
    }

    static func date(from localDate: LocalDate) -> Date {
        localDate.date(in: homeTimeZone)
    }

    static func dateText(_ localDate: LocalDate) -> String {
        String(format: "%04d年%02d月%02d日", localDate.year, localDate.month, localDate.day)
    }

    static func dateText(_ rawValue: Int?) -> String {
        guard let rawValue, let date = try? LocalDate(rawValue: rawValue) else { return "—" }
        return dateText(date)
    }

    static func amountText(_ amount: Decimal, currencyCode: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
        return currencyCode.map { "\(value) \($0)" } ?? value
    }

    static func editableAmountText(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }

    static func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[+-]?(?:(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)|(?:[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?))(?:[eE][+-]?[0-9]+)?$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func parseReminderTime(_ value: String) -> ReminderTime? {
        let bytes = Array(value.utf8)
        guard bytes.count == 5,
              bytes[2] == 58,
              bytes[0..<2].allSatisfy({ (48...57).contains($0) }),
              bytes[3..<5].allSatisfy({ (48...57).contains($0) }),
              let hour = Int(String(decoding: bytes[0..<2], as: UTF8.self)),
              let minute = Int(String(decoding: bytes[3..<5], as: UTF8.self)),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return ReminderTime(hour: hour, minute: minute)
    }

    static func parseReminderOffsets(_ value: String) -> [Int]? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let offsets = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard offsets.count == parts.count,
              offsets.allSatisfy({ (0...maximumReminderOffset).contains($0) }) else { return nil }
        return offsets
    }

    static func rawDate(_ date: Date) -> Int {
        localDate(from: date).rawValue
    }

    static func dateRangeText(start: Int, end: Int) -> String {
        "\(dateText(start))–\(dateText(end))"
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct InlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
            .accessibilityLabel("错误：\(message)")
    }
}
