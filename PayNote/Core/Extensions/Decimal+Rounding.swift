import Foundation

extension Decimal {
    /// 通貨の小数桁数を返す
    static func currencyFractionDigits(locale: Locale = .current) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter.maximumFractionDigits
    }

    /// 任意小数桁で丸める
    func roundedAmount(scale: Int, bankersRounding: Bool = false) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, bankersRounding ? .bankers : .plain)
        return result
    }

    /// 通貨小数桁に合わせて丸める
    func roundedAmount(locale: Locale = .current, bankersRounding: Bool = false) -> Decimal {
        roundedAmount(scale: Self.currencyFractionDigits(locale: locale), bankersRounding: bankersRounding)
    }

    var isZero: Bool { self == .zero }

    /// 通貨表示（通貨記号と小数桁数はロケールに従う）
    func currencyString(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        let fractionDigits = Self.currencyFractionDigits(locale: locale)
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }

    /// 通貨の最小単位へ変換した整数値を返す
    func minorUnits(locale: Locale = .current) -> Decimal {
        let scale = Self.powerOfTen(Self.currencyFractionDigits(locale: locale))
        return (self * scale).roundedAmount(scale: 0)
    }

    /// 通貨の最小単位から金額へ戻す
    static func fromMinorUnits(_ minorUnits: Decimal, locale: Locale = .current) -> Decimal {
        let scale = Self.powerOfTen(Self.currencyFractionDigits(locale: locale))
        if scale == 0 {
            return minorUnits
        }
        return (minorUnits / scale).roundedAmount(locale: locale)
    }

    /// 10 の累乗を Decimal で返す
    private static func powerOfTen(_ exponent: Int) -> Decimal {
        if exponent <= 0 {
            return 1
        }
        return (0..<exponent).reduce(Decimal(1)) { value, _ in
            value * 10
        }
    }
}
