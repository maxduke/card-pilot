import Foundation

/// Amount input follows the keyboard's effective number format, including user overrides.
enum AmountInput {
    struct Format: Codable, Equatable {
        var localeIdentifier: String
        var decimalSeparator: String
        var groupingSeparator: String
        var primaryGroupingSize: Int
        var secondaryGroupingSize: Int

        init(locale: Locale = .current) {
            localeIdentifier = locale.identifier
            decimalSeparator = locale.decimalSeparator ?? "."
            groupingSeparator = locale.groupingSeparator ?? ","
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            primaryGroupingSize = formatter.groupingSize > 0 ? formatter.groupingSize : 3
            secondaryGroupingSize = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primaryGroupingSize
        }

        var locale: Locale { Locale(identifier: localeIdentifier) }
        var isValid: Bool {
            !localeIdentifier.isEmpty && !decimalSeparator.isEmpty
                && decimalSeparator != groupingSeparator
                && (1...9).contains(primaryGroupingSize) && (1...9).contains(secondaryGroupingSize)
        }

        static var legacy: Format {
            var format = Format(locale: Locale(identifier: "en_US_POSIX"))
            // The v1 draft grammar allowed comma groups of three, even where the
            // platform's POSIX NumberFormatter disables grouping.
            format.decimalSeparator = "."
            format.groupingSeparator = ","
            format.primaryGroupingSize = 3
            format.secondaryGroupingSize = 3
            return format
        }
    }

    static func text(_ amount: Decimal, locale: Locale = .current) -> String {
        NSDecimalNumber(decimal: amount).stringValue
            .replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    static func text(_ amount: Decimal, format: Format) -> String {
        NSDecimalNumber(decimal: amount).stringValue
            .replacingOccurrences(of: ".", with: format.decimalSeparator)
    }

    static func decimal(_ text: String, locale: Locale = .current) -> Decimal? {
        decimal(text, format: Format(locale: locale))
    }

    static func decimal(_ text: String, format: Format) -> Decimal? {
        guard format.isValid else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(trimmed.map { character -> Character in
            guard character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                  let value = character.wholeNumberValue, (0...9).contains(value) else { return character }
            return Character(String(value))
        })
        let decimalSeparator = format.decimalSeparator
        let groupingSeparator = format.groupingSeparator
        let separator = NSRegularExpression.escapedPattern(for: decimalSeparator)
        var integerPattern = "[0-9]+"
        if !groupingSeparator.isEmpty, digits.contains(groupingSeparator) {
            let grouping = NSRegularExpression.escapedPattern(for: groupingSeparator)
            integerPattern += "|[0-9]{1,\(format.secondaryGroupingSize)}(?:\(grouping)[0-9]{\(format.secondaryGroupingSize)})*\(grouping)[0-9]{\(format.primaryGroupingSize)}"
        }
        // A trailing separator is a valid intermediate input ("12," on a comma keyboard).
        let pattern = "\\A[+-]?(?:(?:\(integerPattern))(?:\(separator)[0-9]*)?|\(separator)[0-9]+)(?:[eE][+-]?[0-9]+)?\\z"
        guard digits.range(of: pattern, options: .regularExpression) != nil else { return nil }
        var normalized = digits
        if !groupingSeparator.isEmpty {
            normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
        }
        normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return value
    }
}
