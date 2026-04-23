import Foundation
import SwiftData

/// E3record 保存・削除・繰り返し処理と集計再計算
@MainActor
enum RecordService {

    // MARK: - Save

    static func save(_ record: E3record, context: ModelContext) {
        guard let card = record.e1card else { return }

        let dates   = BillingService.partDates(record: record, card: card)
        let amounts = BillingService.partAmounts(record: record)

        for (i, (billingDate, amount)) in zip(dates, amounts).enumerated() {
            let invoice = findOrCreateInvoice(card: card, date: billingDate, context: context)
            let payment = findOrCreatePayment(date: billingDate, context: context)
            if invoice.e7payment == nil {
                invoice.e7payment = payment
            }
            let part = E6part(nPartNo: Int16(i + 1), nAmount: amount)
            part.e2invoice = invoice
            part.e3record  = record
            context.insert(part)
        }

        updateShopStats(record.e4shop, amount: record.nAmount, date: record.dateUse)
        updateCategoryStats(record.e5category, amount: record.nAmount, date: record.dateUse)
        recalculateCard(card)
        recalculatePayments(for: card)
    }

    // MARK: - Delete

    static func delete(_ record: E3record, context: ModelContext) {
        let card       = record.e1card
        let invoiceIDs = record.e6parts.compactMap { $0.e2invoice?.id }
        let paymentIDs = record.e6parts.compactMap { $0.e2invoice?.e7payment?.id }

        context.delete(record) // cascades to E6parts

        if let card {
            for inv in card.e2invoices where invoiceIDs.contains(inv.id) && inv.e6parts.isEmpty {
                inv.e7payment = nil
                context.delete(inv)
            }
            recalculateCard(card)
        }
        cleanupEmptyPayments(ids: paymentIDs, context: context)
    }

    // MARK: - Repeat (nRepeat > 0: mark-paid でコピーを翌月以降に作成)

    static func makeRepeatRecord(from source: E3record, context: ModelContext) {
        guard source.nRepeat > 0, let card = source.e1card else { return }
        guard let nextDate = Calendar.current.date(
            byAdding: .month, value: Int(source.nRepeat), to: source.dateUse
        ) else { return }

        let next = E3record(
            dateUse:  nextDate,
            zName:    source.zName,
            zNote:    source.zNote,
            nAmount:  source.nAmount,
            nPayType: source.nPayType,
            nRepeat:  source.nRepeat,
            nAnnual:  source.nAnnual
        )
        next.e1card     = card
        next.e4shop     = source.e4shop
        next.e5category = source.e5category
        context.insert(next)
        save(next, context: context)
    }

    // MARK: - Recalculate

    static func recalculateCard(_ card: E1card) {
        var paid: Decimal = 0, unpaid: Decimal = 0, noCheck: Int16 = 0
        for inv in card.e2invoices {
            if inv.isPaid { paid += inv.sumAmount } else { unpaid += inv.sumAmount }
            noCheck += inv.sumNoCheck
        }
        card.sumPaid    = paid
        card.sumUnpaid  = unpaid
        card.sumNoCheck = noCheck
    }

    static func recalculatePayments(for card: E1card) {
        var seen = Set<String>()
        for inv in card.e2invoices {
            guard let p = inv.e7payment, !seen.contains(p.id) else { continue }
            seen.insert(p.id)
            p.sumAmount  = p.e2invoices.reduce(.zero) { $0 + $1.sumAmount }
            p.sumNoCheck = p.e2invoices.reduce(0)     { $0 + $1.sumNoCheck }
        }
    }

    // MARK: - Private

    private static func findOrCreateInvoice(card: E1card, date: Date, context: ModelContext) -> E2invoice {
        let day = Calendar.current.startOfDay(for: date)
        if let ex = card.e2invoices.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            return ex
        }
        let inv = E2invoice(date: day)
        inv.e1card = card
        context.insert(inv)
        return inv
    }

    private static func findOrCreatePayment(date: Date, context: ModelContext) -> E7payment {
        let day  = Calendar.current.startOfDay(for: date)
        let desc = FetchDescriptor<E7payment>(predicate: #Predicate { $0.date == day })
        if let ex = try? context.fetch(desc).first { return ex }
        let p = E7payment(date: day)
        context.insert(p)
        return p
    }

    private static func cleanupEmptyPayments(ids: [String], context: ModelContext) {
        let desc = FetchDescriptor<E7payment>()
        guard let all = try? context.fetch(desc) else { return }
        for p in all where ids.contains(p.id) && p.e2invoices.isEmpty {
            context.delete(p)
        }
    }

    private static func updateShopStats(_ shop: E4shop?, amount: Decimal, date: Date) {
        guard let shop else { return }
        shop.sortDate    = date
        shop.sortCount  += 1
        shop.sortAmount += amount
        shop.sortName    = shop.zName
    }

    private static func updateCategoryStats(_ cat: E5category?, amount: Decimal, date: Date) {
        guard let cat else { return }
        cat.sortDate    = date
        cat.sortCount  += 1
        cat.sortAmount += amount
        cat.sortName    = cat.zName
    }
}
