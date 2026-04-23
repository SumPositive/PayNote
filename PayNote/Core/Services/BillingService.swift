import Foundation

/// クレジットカードの支払日計算
enum BillingService {

    /// 利用日とカード設定から n 番目の支払日を返す（partOffset=0 が 1 回目）
    static func billingDate(useDate: Date, card: E1card, partOffset: Int = 0) -> Date {
        if card.isDebit {
            return Calendar.current.startOfDay(for: useDate)
        }
        let cal = Calendar.current
        let dc  = cal.dateComponents([.year, .month, .day], from: useDate)
        let useDay   = dc.day   ?? 1
        let useMonth = dc.month ?? 1
        let useYear  = dc.year  ?? 2024

        let closingDay: Int = card.nClosingDay == 29
            ? daysInMonth(year: useYear, month: useMonth)
            : Int(card.nClosingDay)

        let overClose   = useDay > closingDay ? 1 : 0
        let totalOffset = Int(card.nPayMonth) + overClose + partOffset

        return makeDate(year: useYear, month: useMonth + totalOffset, payDay: Int(card.nPayDay))
    }

    /// E3record の各 E6part に対応する支払日リストを返す
    static func partDates(record: E3record, card: E1card) -> [Date] {
        (0..<partCount(for: record.payType)).map {
            billingDate(useDate: record.dateUse, card: card, partOffset: $0)
        }
    }

    /// E3record の各 E6part に対応する金額リストを返す
    static func partAmounts(record: E3record) -> [Decimal] {
        switch record.payType {
        case .lumpSum:
            return [record.nAmount]
        case .twoPayments:
            let half      = (record.nAmount / 2).roundedAmount()
            let remainder = record.nAmount - half
            return [half, remainder]
        }
    }

    static func partCount(for payType: PayType) -> Int {
        switch payType {
        case .lumpSum:     return 1
        case .twoPayments: return 2
        }
    }

    // MARK: - Private

    private static func daysInMonth(year: Int, month: Int) -> Int {
        var dc = DateComponents()
        dc.year = year; dc.month = month + 1; dc.day = 0
        return Calendar.current.dateComponents([.day],
            from: Calendar.current.date(from: dc)!).day ?? 28
    }

    private static func makeDate(year: Int, month: Int, payDay: Int) -> Date {
        let cal  = Calendar.current
        var dc   = DateComponents(); dc.year = year; dc.month = month
        let base = cal.date(from: dc) ?? Date()
        let bc   = cal.dateComponents([.year, .month], from: base)
        let y    = bc.year  ?? year
        let m    = bc.month ?? 1
        let maxD = daysInMonth(year: y, month: m)
        var fd   = DateComponents()
        fd.year = y; fd.month = m
        fd.day  = payDay == 29 ? maxD : min(payDay, maxD)
        return cal.date(from: fd) ?? base
    }
}
