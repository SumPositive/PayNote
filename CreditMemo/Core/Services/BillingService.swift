import Foundation

/// クレジットカードの支払日計算
enum BillingService {
    // 決済手段未選択時の仮スケジュール（27日締め・翌月27日払い）
    static let fallbackClosingDay: Int16 = 27
    static let fallbackPayDay: Int16 = 27
    static let fallbackPayMonth: Int16 = 1

    /// 利用日とカード設定から n 番目の支払日を返す（partOffset=0 が 1 回目）
    static func billingDate(useDate: Date, card: E1card, partOffset: Int = 0) -> Date {
        if card.isDebit {
            return Calendar.current.startOfDay(for: useDate)
        }
        // 請求方式ごとに計算方法を切り替える
        if card.billingType == .afterDays {
            return billingDateAfterDays(
                useDate: useDate,
                offsetDays: card.offsetDays ?? Int(fallbackPayDay),
                partOffset: partOffset
            )
        }
        return billingDate(
            useDate: useDate,
            closingDay: card.nClosingDay,
            payDay: card.nPayDay,
            payMonth: card.nPayMonth,
            partOffset: partOffset
        )
    }

    /// 決済手段未選択を含めた支払日を返す（未選択時は仮スケジュール）
    static func billingDate(useDate: Date, card: E1card?, partOffset: Int = 0) -> Date {
        if let card {
            return billingDate(useDate: useDate, card: card, partOffset: partOffset)
        }
        return billingDate(
            useDate: useDate,
            closingDay: fallbackClosingDay,
            payDay: fallbackPayDay,
            payMonth: fallbackPayMonth,
            partOffset: partOffset
        )
    }

    /// 日付計算の本体
    private static func billingDate(
        useDate: Date,
        closingDay: Int16,
        payDay: Int16,
        payMonth: Int16,
        partOffset: Int
    ) -> Date {
        let cal = Calendar.current
        let dc  = cal.dateComponents([.year, .month, .day], from: useDate)
        let useDay   = dc.day   ?? 1
        let useMonth = dc.month ?? 1
        let useYear  = dc.year  ?? 2024

        let closingDayValue: Int = closingDay == 29
            ? daysInMonth(year: useYear, month: useMonth)
            : Int(closingDay)

        let overClose = closingDayValue < useDay ? 1 : 0
        let totalOffset = Int(payMonth) + overClose + partOffset

        return makeDate(year: useYear, month: useMonth + totalOffset, payDay: Int(payDay))
    }

    /// 都度 n 日後型の請求日計算
    private static func billingDateAfterDays(
        useDate: Date,
        offsetDays: Int,
        partOffset: Int
    ) -> Date {
        let cal = Calendar.current
        let baseDate = cal.startOfDay(for: useDate)
        let monthShifted = cal.date(byAdding: .month, value: partOffset, to: baseDate) ?? baseDate
        let billed = cal.date(byAdding: .day, value: offsetDays, to: monthShifted) ?? monthShifted
        return cal.startOfDay(for: billed)
    }

    /// E3record の各 E6part に対応する支払日リストを返す
    static func partDates(record: E3record, card: E1card) -> [Date] {
        (0..<partCount(for: record.payType)).map {
            billingDate(useDate: record.dateUse, card: card, partOffset: $0)
        }
    }

    /// E3record の各 E6part に対応する支払日リストを返す（未選択対応）
    static func partDates(record: E3record, card: E1card?) -> [Date] {
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
