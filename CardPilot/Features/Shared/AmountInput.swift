import Foundation

/// Amount input follows the keyboard's locale; persisted amounts remain exact Decimals.
enum AmountInput {
    static func text(_ amount: Decimal, locale: Locale = .current) -> String {
        NSDecimalNumber(decimal: amount).stringValue
            .replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    static func decimal(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(trimmed.map { character -> Character in
            guard character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                  let value = character.wholeNumberValue, (0...9).contains(value) else { return character }
            return Character(String(value))
        })
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        let separator = NSRegularExpression.escapedPattern(for: decimalSeparator)
        var integerPattern = "[0-9]+"
        if !groupingSeparator.isEmpty, groupingSeparator != decimalSeparator, digits.contains(groupingSeparator) {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            let primarySize = max(1, formatter.groupingSize)
            let secondarySize = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primarySize
            let grouping = NSRegularExpression.escapedPattern(for: groupingSeparator)
            integerPattern += "|[0-9]{1,\(secondarySize)}(?:\(grouping)[0-9]{\(secondarySize)})*\(grouping)[0-9]{\(primarySize)}"
        }
        // A trailing separator is a valid intermediate input ("12," on a comma keyboard).
        let pattern = "\\A[+-]?(?:(?:\(integerPattern))(?:\(separator)[0-9]*)?|\(separator)[0-9]+)(?:[eE][+-]?[0-9]+)?\\z"
        guard digits.range(of: pattern, options: .regularExpression) != nil else { return nil }
        var normalized = digits
        if !groupingSeparator.isEmpty, groupingSeparator != decimalSeparator {
            normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
        }
        normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return value
    }
}
