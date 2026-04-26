import Foundation
import SwiftData

/// E3record 保存・削除・繰り返し処理と集計再計算
@MainActor
enum RecordService {
    /// 1件の明細から影響範囲を再構築するための退避情報
    private struct BillingSnapshot {
        var touchedCardIDs: Set<String> = []
        var touchedPaymentDates: Set<Date> = []
        var invoicePaidByKey: [String: Bool] = [:]
        var paymentPaidByDate: [Date: Bool] = [:]
        var partNoCheckByPartNo: [Int16: Int16] = [:]
    }

    // MARK: - Save

    static func save(_ record: E3record, context: ModelContext) {
        rebuildBilling(for: record, context: context)
        updateShopStats(record.e4shop, amount: record.nAmount, date: record.dateUse)
        let cats = record.e5categories.isEmpty ? [record.e5category].compactMap { $0 } : record.e5categories
        for cat in cats { updateCategoryStats(cat, amount: record.nAmount, date: record.dateUse) }
    }

    // MARK: - Delete

    static func delete(_ record: E3record, context: ModelContext) {
        let snapshot = snapshot(for: record)
        context.delete(record)
        cleanupBilling(snapshot: snapshot, context: context)
    }

    /// 編集前の旧パーツだけを除去し、請求・支払の孤児データを掃除する
    static func removeParts(of record: E3record, context: ModelContext) {
        let snapshot = snapshot(for: record)
        removeExistingParts(of: record, context: context)
        cleanupBilling(snapshot: snapshot, context: context)
    }

    /// 既存データの整合性を保つため、明細が空の請求/支払を掃除する
    static func cleanupOrphanBilling(context: ModelContext) {
        let invoiceDesc = FetchDescriptor<E2invoice>()
        let paymentDesc = FetchDescriptor<E7payment>()
        let cardDesc = FetchDescriptor<E1card>()
        let invoices = (try? context.fetch(invoiceDesc)) ?? []
        let payments = (try? context.fetch(paymentDesc)) ?? []
        let cards = (try? context.fetch(cardDesc)) ?? []

        for invoice in invoices where invoice.e6parts.isEmpty {
            invoice.e7payment = nil
            context.delete(invoice)
        }
        for payment in payments where payment.e2invoices.isEmpty {
            context.delete(payment)
        }
        for payment in payments where !payment.e2invoices.isEmpty {
            recalculatePayment(payment)
            payment.isPaid = payment.e2invoices.allSatisfy { $0.isPaid }
        }
        for card in cards {
            recalculateCard(card)
        }
    }

    /// 請求パーツ未作成の明細を補完する（決済手段の有無を問わない）
    static func ensureBillingGenerated(context: ModelContext) {
        let recordDesc = FetchDescriptor<E3record>(
            predicate: #Predicate<E3record> { $0.e6parts.isEmpty }
        )
        let records = (try? context.fetch(recordDesc)) ?? []
        for record in records {
            rebuildBilling(for: record, context: context)
        }
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

    // MARK: - Rebuild

    static func rebuildBilling(context: ModelContext) {
        let recordDesc = FetchDescriptor<E3record>(sortBy: [SortDescriptor(\E3record.dateUse)])
        let records = (try? context.fetch(recordDesc)) ?? []
        for record in records {
            rebuildBilling(for: record, context: context)
        }
        cleanupOrphanBilling(context: context)
    }

    static func rebuildBilling(for record: E3record, context: ModelContext) {
        let snapshot = snapshot(for: record)
        removeExistingParts(of: record, context: context)

        let dates = BillingService.partDates(record: record, card: record.e1card)
        let amounts = BillingService.partAmounts(record: record)
        for (index, pair) in zip(dates.indices, zip(dates, amounts)) {
            let billingDate = Calendar.current.startOfDay(for: pair.0)
            let amount = pair.1
            let partNo = Int16(index + 1)
            let invoice = findOrCreateInvoice(
                card: record.e1card,
                date: billingDate,
                fallbackInvoicePaid: snapshot.invoicePaidByKey[invoiceKey(cardID: record.e1card?.id, date: billingDate)],
                fallbackPaymentPaid: snapshot.paymentPaidByDate[billingDate],
                context: context
            )
            let payment = findOrCreatePayment(
                date: billingDate,
                fallbackPaid: snapshot.paymentPaidByDate[billingDate],
                context: context
            )
            if invoice.e7payment == nil {
                invoice.e7payment = payment
            }
            let part = E6part(nPartNo: partNo, nAmount: amount)
            part.nNoCheck = snapshot.partNoCheckByPartNo[partNo] ?? 1
            part.e2invoice = invoice
            part.e3record = record
            context.insert(part)
        }

        var touchedCardIDs = snapshot.touchedCardIDs
        if let cardID = record.e1card?.id {
            touchedCardIDs.insert(cardID)
        }
        var touchedPaymentDates = snapshot.touchedPaymentDates
        for date in dates {
            touchedPaymentDates.insert(Calendar.current.startOfDay(for: date))
        }
        recalculateTouchedBilling(cardIDs: touchedCardIDs, paymentDates: touchedPaymentDates, context: context)
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

    private static func snapshot(for record: E3record) -> BillingSnapshot {
        var snapshot = BillingSnapshot()
        for part in record.e6parts {
            snapshot.partNoCheckByPartNo[part.nPartNo] = part.nNoCheck
            if let invoice = part.e2invoice {
                let key = invoiceKey(cardID: invoice.e1card?.id, date: invoice.date)
                snapshot.invoicePaidByKey[key] = invoice.isPaid
                if let cardID = invoice.e1card?.id {
                    snapshot.touchedCardIDs.insert(cardID)
                }
                if let payment = invoice.e7payment {
                    let day = Calendar.current.startOfDay(for: payment.date)
                    snapshot.paymentPaidByDate[day] = payment.isPaid
                    snapshot.touchedPaymentDates.insert(day)
                } else {
                    snapshot.touchedPaymentDates.insert(Calendar.current.startOfDay(for: invoice.date))
                }
            }
        }
        if let cardID = record.e1card?.id {
            snapshot.touchedCardIDs.insert(cardID)
        }
        for date in BillingService.partDates(record: record, card: record.e1card) {
            snapshot.touchedPaymentDates.insert(Calendar.current.startOfDay(for: date))
        }
        return snapshot
    }

    private static func removeExistingParts(of record: E3record, context: ModelContext) {
        for part in record.e6parts {
            if let invoice = part.e2invoice {
                invoice.e6parts.removeAll { $0.id == part.id }
            }
            part.e2invoice = nil
            part.e3record = nil
            context.delete(part)
        }
        record.e6parts.removeAll()
    }

    private static func cleanupBilling(snapshot: BillingSnapshot, context: ModelContext) {
        recalculateTouchedBilling(
            cardIDs: snapshot.touchedCardIDs,
            paymentDates: snapshot.touchedPaymentDates,
            context: context
        )
    }

    private static func recalculateTouchedBilling(
        cardIDs: Set<String>,
        paymentDates: Set<Date>,
        context: ModelContext
    ) {
        let cardDesc = FetchDescriptor<E1card>()
        let paymentDesc = FetchDescriptor<E7payment>()
        let invoiceDesc = FetchDescriptor<E2invoice>()
        let cards = (try? context.fetch(cardDesc)) ?? []
        let payments = (try? context.fetch(paymentDesc)) ?? []
        let invoices = (try? context.fetch(invoiceDesc)) ?? []

        for invoice in invoices where invoice.e6parts.isEmpty {
            if let payment = invoice.e7payment {
                payment.e2invoices.removeAll { $0.id == invoice.id }
            }
            invoice.e7payment = nil
            context.delete(invoice)
        }

        for card in cards where cardIDs.contains(card.id) {
            recalculateCard(card)
        }

        for payment in payments {
            let day = Calendar.current.startOfDay(for: payment.date)
            if payment.e2invoices.isEmpty {
                context.delete(payment)
                continue
            }
            if paymentDates.contains(day) {
                recalculatePayment(payment)
                payment.isPaid = payment.e2invoices.allSatisfy { $0.isPaid }
            }
        }
    }

    private static func invoiceKey(cardID: String?, date: Date) -> String {
        let rawCardID = cardID ?? "__no_card__"
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(rawCardID)#\(day)"
    }

    private static func findOrCreateInvoice(
        card: E1card?,
        date: Date,
        fallbackInvoicePaid: Bool?,
        fallbackPaymentPaid: Bool?,
        context: ModelContext
    ) -> E2invoice {
        let day = Calendar.current.startOfDay(for: date)
        if let card {
            if let ex = card.e2invoices.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                return ex
            }
            let inv = E2invoice(date: day)
            inv.e1card = card
            inv.isPaid = fallbackInvoicePaid ?? fallbackPaymentPaid ?? false
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
        inv.isPaid = fallbackInvoicePaid ?? fallbackPaymentPaid ?? false
        context.insert(inv)
        return inv
    }

    private static func findOrCreatePayment(
        date: Date,
        fallbackPaid: Bool?,
        context: ModelContext
    ) -> E7payment {
        let day  = Calendar.current.startOfDay(for: date)
        let desc = FetchDescriptor<E7payment>(predicate: #Predicate { $0.date == day })
        if let ex = try? context.fetch(desc).first { return ex }
        let p = E7payment(date: day, isPaid: fallbackPaid ?? false)
        context.insert(p)
        return p
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
