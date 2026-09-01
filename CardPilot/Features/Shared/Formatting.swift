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

struct CurrencyOption: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String

    var id: String { code }

    static let commonCodes = ["CNY", "HKD", "USD", "EUR", "JPY", "GBP"]

    static let all: [CurrencyOption] = {
        let locale = Locale.current
        return Locale.commonISOCurrencyCodes
            .filter { Locale.Currency($0).isISOCurrency }
            .map { code in
                let name = locale.localizedString(forCurrencyCode: code) ?? code
                let symbol = Locale(identifier: "\(locale.identifier)@currency=\(code)").currencySymbol ?? code
                return CurrencyOption(code: code, name: name, symbol: symbol)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func find(_ code: String) -> CurrencyOption {
        all.first { $0.code == code } ?? CurrencyOption(code: code, name: code, symbol: code)
    }
}

struct CurrencyPickerView: View {
    @Binding private var selection: String
    private let title: String
    @State private var showingSheet = false

    init(selection: Binding<String>, title: String = "额度币种") {
        _selection = selection
        self.title = title
    }

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                CurrencyCodeLabel(code: selection)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel("\(title)：\(selection)")
        .sheet(isPresented: $showingSheet) {
            CurrencyPickerSheet(selection: $selection, title: title)
        }
    }
}

private struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let title: String
    @AppStorage("cardPilot.recentCurrencies") private var recentValue = ""
    @State private var query = ""

    private var recentCodes: [String] {
        recentValue.split(separator: ",").map(String.init).filter { code in
            CurrencyOption.all.contains { option in option.code == code }
        }
    }

    private var recentOptions: [CurrencyOption] {
        recentCodes.map(CurrencyOption.find)
    }

    private var commonOptions: [CurrencyOption] {
        CurrencyOption.commonCodes.compactMap { code in CurrencyOption.all.first { $0.code == code } }
    }

    private var filteredOptions: [CurrencyOption] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return CurrencyOption.all }
        return CurrencyOption.all.filter {
            $0.code.localizedCaseInsensitiveContains(normalized)
                || $0.name.localizedCaseInsensitiveContains(normalized)
                || $0.symbol.localizedCaseInsensitiveContains(normalized)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !recentOptions.isEmpty {
                        Section("最近使用") {
                            ForEach(recentOptions) { option in optionRow(option) }
                        }
                    }
                    Section("常用币种") {
                        ForEach(commonOptions) { option in optionRow(option) }
                    }
                    Section("全部币种") {
                        ForEach(CurrencyOption.all.filter { !CurrencyOption.commonCodes.contains($0.code) }) { option in
                            optionRow(option)
                        }
                    }
                } else {
                    Section {
                        ForEach(filteredOptions) { option in optionRow(option) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜索币种、代码或符号")
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: CurrencyOption) -> some View {
        Button {
            selection = option.code
            recordRecent(option.code)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(option.symbol)
                    .font(.headline.monospacedDigit())
                    .frame(width: 30)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                    Text(option.code)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if option.code == selection {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.name)，\(option.code)")
    }

    private func recordRecent(_ code: String) {
        var codes = recentCodes.filter { $0 != code }
        codes.insert(code, at: 0)
        recentValue = codes.prefix(8).joined(separator: ",")
    }
}

private struct CurrencyCodeLabel: View {
    let code: String

    var body: some View {
        HStack(spacing: 5) {
            Text(CurrencyOption.find(code).symbol)
                .font(.subheadline.monospacedDigit())
            Text(code)
                .font(.subheadline.monospaced())
        }
    }
}

struct BankBadge: View {
    let name: String
    let monogram: String

    init(name: String, monogram: String? = nil) {
        self.name = name
        self.monogram = monogram ?? String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    init(bank: Bank) {
        self.init(name: bank.name, monogram: bank.presetCode.flatMap { code in
            BankPreset.catalog.first { $0.code == code }?.monogram
        })
    }

    var body: some View {
        Text(monogram)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                LinearGradient(
                    colors: [.indigo, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityLabel("\(name)图标")
    }
}

struct CardNetworkBadge: View {
    let displayName: String
    let code: String

    init(network: CardNetwork) {
        displayName = network.displayName
        code = network.code
    }

    init(displayName: String, code: String = "") {
        self.displayName = displayName
        self.code = code
    }

    var body: some View {
        Text(shortName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(displayName)
    }

    private var shortName: String {
        switch code {
        case "unionpay": return "银联"
        case "visa": return "VISA"
        case "mastercard": return "MC"
        case "amex": return "AMEX"
        case "jcb": return "JCB"
        default: return String(displayName.prefix(6))
        }
    }
}

struct CardNetworksBadges: View {
    let networks: [CardNetwork]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(networks, id: \.id) { network in
                CardNetworkBadge(network: network)
            }
        }
    }
}

func cardNetworkSummary(_ networks: [CardNetwork]) -> String {
    networks.map(\.displayName).joined(separator: " + ")
}

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
