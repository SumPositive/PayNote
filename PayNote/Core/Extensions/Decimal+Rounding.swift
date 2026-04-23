import Foundation

extension Decimal {
    /// 円金額として丸める（偶数丸め or 四捨五入）
    func roundedAmount(bankersRounding: Bool = false) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, 0, bankersRounding ? .bankers : .plain)
        return result
    }

    var isZero: Bool { self == .zero }

    /// 符号付き円表示 (例: -¥1,234)
    func currencyString(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.maximumFractionDigits = 0
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}
