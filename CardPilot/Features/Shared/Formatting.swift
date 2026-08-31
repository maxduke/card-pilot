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

    static func decimal(_ text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
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
