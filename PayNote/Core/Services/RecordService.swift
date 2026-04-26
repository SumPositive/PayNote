import Foundation
import SwiftData

/// E3record 保存・削除・繰り返し処理と集計再計算
@MainActor
enum RecordService {

    // MARK: - Save

    static func save(_ record: E3record, context: ModelContext) {
        let card = record.e1card
        let dates   = BillingService.partDates(record: record, card: card)
        let amounts = BillingService.partAmounts(record: record)
        var touchedPayments: [String: E7payment] = [:]

        for (i, (billingDate, amount)) in zip(dates, amounts).enumerated() {
            let invoice = findOrCreateInvoice(card: card, date: billingDate, context: context)
            let payment = findOrCreatePayment(date: billingDate, context: context)
            touchedPayments[payment.id] = payment
            if invoice.e7payment == nil {
                invoice.e7payment = payment
            }
            let part = E6part(nPartNo: Int16(i + 1), nAmount: amount)
            part.e2invoice = invoice
            part.e3record  = record
            context.insert(part)
        }

        updateShopStats(record.e4shop, amount: record.nAmount, date: record.dateUse)
        let cats = record.e5categories.isEmpty ? [record.e5category].compactMap { $0 } : record.e5categories
        for cat in cats { updateCategoryStats(cat, amount: record.nAmount, date: record.dateUse) }
        if let card {
            recalculateCard(card)
        }
        for payment in touchedPayments.values {
            recalculatePayment(payment)
        }
    }

    // MARK: - Delete

    static func delete(_ record: E3record, context: ModelContext) {
        let card       = record.e1card
        let invoiceIDs = record.e6parts.compactMap { $0.e2invoice?.id }
        let paymentIDs = record.e6parts.compactMap { $0.e2invoice?.e7payment?.id }

        context.delete(record) // cascades to E6parts

        if let card {
            recalculateCard(card)
        }
        cleanupEmptyInvoices(ids: invoiceIDs, context: context)
        recalculatePayments(ids: paymentIDs, context: context)
        cleanupEmptyPayments(ids: paymentIDs, context: context)
    }

    /// 編集前の旧パーツだけを除去し、請求・支払の孤児データを掃除する
    static func removeParts(of record: E3record, context: ModelContext) {
        let card = record.e1card
        let invoiceIDs = record.e6parts.compactMap { $0.e2invoice?.id }
        let paymentIDs = record.e6parts.compactMap { $0.e2invoice?.e7payment?.id }

        for part in record.e6parts {
            if let invoice = part.e2invoice {
                invoice.e6parts.removeAll { $0.id == part.id }
            }
            part.e2invoice = nil
            part.e3record = nil
            context.delete(part)
        }
        record.e6parts.removeAll()

        if let card {
            recalculateCard(card)
        }
        cleanupEmptyInvoices(ids: invoiceIDs, context: context)
        recalculatePayments(ids: paymentIDs, context: context)
        cleanupEmptyPayments(ids: paymentIDs, context: context)
    }

    /// 既存データの整合性を保つため、明細が空の請求/支払を掃除する
    static func cleanupOrphanBilling(context: ModelContext) {
        let desc = FetchDescriptor<E2invoice>()
        guard let invoices = try? context.fetch(desc) else { return }

        var touchedPayments = Set<String>()
        var touchedCards: [String: E1card] = [:]

        for invoice in invoices where invoice.e6parts.isEmpty {
            if let paymentID = invoice.e7payment?.id {
                touchedPayments.insert(paymentID)
            }
            if let card = invoice.e1card {
                touchedCards[card.id] = card
            }
            invoice.e7payment = nil
            context.delete(invoice)
        }

        for card in touchedCards.values {
            recalculateCard(card)
        }
        let paymentIDs = Array(touchedPayments)
        recalculatePayments(ids: paymentIDs, context: context)
        cleanupEmptyPayments(ids: paymentIDs, context: context)
    }

    // MARK: - Repeat (nRepeat > 0: mark-paid でコピーを翌月以降に作成)

    static func makeRepeatRecord(from source: E3record, context: ModelContext) {
        guard 0 < source.nRepeat else { return }
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
        next.e1card        = source.e1card
        next.e4shop        = source.e4shop
        next.e5category    = source.e5category
        next.e5categories  = source.e5categories
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
            guard let payment = inv.e7payment else { continue }
            if seen.contains(payment.id) { continue }
            seen.insert(payment.id)
            recalculatePayment(payment)
        }
    }

    // MARK: - Private

    private static func findOrCreateInvoice(card: E1card?, date: Date, context: ModelContext) -> E2invoice {
        let day = Calendar.current.startOfDay(for: date)
        if let card {
            if let ex = card.e2invoices.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                return ex
            }
            let inv = E2invoice(date: day)
            inv.e1card = card
            context.insert(inv)
            return inv
        }

        let desc = FetchDescriptor<E2invoice>(
            predicate: #Predicate { $0.date == day && $0.e1card == nil }
        )
        if let ex = try? context.fetch(desc).first {
            return ex
        }

        let inv = E2invoice(date: day)
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

    private static func cleanupEmptyInvoices(ids: [String], context: ModelContext) {
        let desc = FetchDescriptor<E2invoice>()
        guard let all = try? context.fetch(desc) else { return }
        for invoice in all where ids.contains(invoice.id) && invoice.e6parts.isEmpty {
            invoice.e7payment = nil
            context.delete(invoice)
        }
    }

    private static func recalculatePayments(ids: [String], context: ModelContext) {
        if ids.isEmpty {
            return
        }
        let desc = FetchDescriptor<E7payment>()
        guard let all = try? context.fetch(desc) else { return }
        for payment in all where ids.contains(payment.id) {
            recalculatePayment(payment)
        }
    }

    private static func recalculatePayment(_ payment: E7payment) {
        payment.sumAmount = payment.e2invoices.reduce(.zero) { $0 + $1.sumAmount }
        payment.sumNoCheck = payment.e2invoices.reduce(0) { $0 + $1.sumNoCheck }
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
