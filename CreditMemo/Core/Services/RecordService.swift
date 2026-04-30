import Foundation
import SwiftData

/// E3record 保存・削除・繰り返し処理と集計再計算
@MainActor
enum RecordService {
    /// 1件の明細から影響範囲を再構築するための退避情報
    private struct BillingSnapshot {
        var touchedCardIDs: Set<String> = []
        var touchedPaymentKeys: Set<String> = []
        var invoicePaidByKey: [String: Bool] = [:]
        var paymentPaidByKey: [String: Bool] = [:]
        var partNoCheckByPartNo: [Int16: Int16] = [:]
    }

    // MARK: - Save

    static func save(_ record: E3record, context: ModelContext) throws {
        // 1回の保存操作で派生データ更新まで完結させる
        // 新規/修正の入力順を更新日時で保持する
        record.dateUpdate = Date()
        rebuildBilling(for: record, context: context)
        updateShopStats(record.e4shop, amount: record.nAmount, date: record.dateUse)
        let cats = record.e5categories.isEmpty ? [record.e5category].compactMap { $0 } : record.e5categories
        for cat in cats { updateCategoryStats(cat, amount: record.nAmount, date: record.dateUse) }
        try commit(context)
    }

    // MARK: - Delete

    static func delete(_ record: E3record, context: ModelContext) throws {
        let snapshot = snapshot(for: record)
        context.delete(record)
        cleanupBilling(snapshot: snapshot, context: context)
        try commit(context)
    }

    /// 指定年数より古い履歴を削除する
    static func deleteRecords(olderThanYears years: Int, context: ModelContext) throws {
        let calendar = Calendar.current
        let now = Date()
        guard let cutoff = calendar.date(byAdding: .year, value: -years, to: now) else {
            return
        }

        let descriptor = FetchDescriptor<E3record>(
            predicate: #Predicate<E3record> { $0.dateUse < cutoff }
        )
        let oldRecords = (try? context.fetch(descriptor)) ?? []
        if oldRecords.isEmpty {
            return
        }

        for record in oldRecords {
            let snapshot = snapshot(for: record)
            context.delete(record)
            cleanupBilling(snapshot: snapshot, context: context)
        }
        try commit(context)
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
        var invoices = (try? context.fetch(invoiceDesc)) ?? []
        var payments = (try? context.fetch(paymentDesc)) ?? []
        let cards = (try? context.fetch(cardDesc)) ?? []

        for invoice in invoices where invoice.e6parts.isEmpty {
            clearInvoiceState(invoice)
            invoice.e7payment = nil
            context.delete(invoice)
        }
        // 同一の請求キーを1件へ統合する
        invoices = (try? context.fetch(invoiceDesc)) ?? []
        normalizeInvoices(invoices, context: context)
        for payment in payments where payment.e2invoices.isEmpty {
            clearPaymentState(payment)
            context.delete(payment)
        }
        // 同一の支払キーを1件へ統合する
        payments = (try? context.fetch(paymentDesc)) ?? []
        normalizePayments(payments, context: context)
        payments = (try? context.fetch(paymentDesc)) ?? []
        for payment in payments where !payment.e2invoices.isEmpty {
            recalculatePayment(payment)
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

    static func makeRepeatRecord(from source: E3record, context: ModelContext) throws {
        // 既存呼び出し互換のため公開するが、保存は最後に1回だけ行う
        _ = insertRepeatRecordIfNeeded(from: source, context: context)
        try commit(context)
    }

    /// 請求グループ単位で未払/済みを切り替える
    static func setInvoicesPaid(
        _ invoices: [E2invoice],
        isPaid: Bool,
        context: ModelContext
    ) throws {
        for invoice in invoices {
            moveInvoice(invoice, toPaid: isPaid, context: context)
            if isPaid {
                for part in invoice.e6parts {
                    if let record = part.e3record {
                        _ = insertRepeatRecordIfNeeded(from: record, context: context)
                    }
                }
            }
        }

        for invoice in invoices {
            if let card = invoice.e1card {
                recalculateCard(card)
            }
        }

        try commit(context)
    }

    /// 請求1件単位で未払/済みを切り替える
    static func setInvoicePaid(
        _ invoice: E2invoice,
        isPaid: Bool,
        context: ModelContext
    ) throws {
        moveInvoice(invoice, toPaid: isPaid, context: context)
        if isPaid {
            for part in invoice.e6parts {
                if let record = part.e3record {
                    _ = insertRepeatRecordIfNeeded(from: record, context: context)
                }
            }
        }
        if let card = invoice.e1card {
            recalculateCard(card)
        }
        try commit(context)
    }

    // MARK: - Repeat (nRepeat > 0: mark-paid でコピーを翌月以降に作成)

    private static func insertRepeatRecordIfNeeded(from source: E3record, context: ModelContext) -> E3record? {
        guard 0 < source.nRepeat else { return nil }
        guard let nextDate = Calendar.current.date(
            byAdding: .month, value: Int(source.nRepeat), to: source.dateUse
        ) else { return nil }

        let existsNext = source.e1card?.e3records.contains(where: {
            Calendar.current.isDate($0.dateUse, equalTo: nextDate, toGranularity: .month)
        }) ?? false
        if existsNext {
            return nil
        }

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
        // 繰り返し生成も同じ保存単位に含める
        rebuildBilling(for: next, context: context)
        updateShopStats(next.e4shop, amount: next.nAmount, date: next.dateUse)
        let cats = next.e5categories.isEmpty ? [next.e5category].compactMap { $0 } : next.e5categories
        for cat in cats {
            updateCategoryStats(cat, amount: next.nAmount, date: next.dateUse)
        }
        return next
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
            let bank = record.e1card?.e8bank
            let invoicePaid = snapshot.invoicePaidByKey[
                invoiceKey(cardID: record.e1card?.id, date: billingDate, isPaid: true)
            ] ?? snapshot.invoicePaidByKey[
                invoiceKey(cardID: record.e1card?.id, date: billingDate, isPaid: false)
            ] ?? false
            let invoice = findOrCreateInvoice(
                card: record.e1card,
                date: billingDate,
                fallbackInvoicePaid: invoicePaid,
                fallbackPaymentPaid: snapshot.paymentPaidByKey[
                    paymentKey(bankID: bank?.id, date: billingDate, isPaid: invoicePaid)
                ],
                context: context
            )
            let payment = findOrCreatePayment(
                date: billingDate,
                bank: bank,
                isPaid: invoice.isPaid,
                fallbackPaid: snapshot.paymentPaidByKey[
                    paymentKey(bankID: bank?.id, date: billingDate, isPaid: invoice.isPaid)
                ],
                context: context
            )
            // 口座変更時は既存invoiceでも支払先を最新のpaymentへ張り替える
            if invoice.e7payment?.id != payment.id {
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
        var touchedPaymentKeys = snapshot.touchedPaymentKeys
        for date in dates {
            let day = Calendar.current.startOfDay(for: date)
            let paid = snapshot.invoicePaidByKey[
                invoiceKey(cardID: record.e1card?.id, date: day, isPaid: true)
            ] ?? snapshot.invoicePaidByKey[
                invoiceKey(cardID: record.e1card?.id, date: day, isPaid: false)
            ] ?? false
            touchedPaymentKeys.insert(paymentKey(bankID: record.e1card?.e8bank?.id, date: day, isPaid: paid))
        }
        recalculateTouchedBilling(cardIDs: touchedCardIDs, paymentKeys: touchedPaymentKeys, context: context)
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
                snapshot.invoicePaidByKey[
                    invoiceKey(cardID: invoice.e1card?.id, date: invoice.date, isPaid: invoice.isPaid)
                ] = invoice.isPaid
                if let cardID = invoice.e1card?.id {
                    snapshot.touchedCardIDs.insert(cardID)
                }
                if let payment = invoice.e7payment {
                    let key = paymentKey(bankID: payment.e8bank?.id, date: payment.date, isPaid: payment.isPaid)
                    snapshot.touchedPaymentKeys.insert(key)
                    snapshot.paymentPaidByKey[key] = payment.isPaid
                }
            }
        }
        if let cardID = record.e1card?.id {
            snapshot.touchedCardIDs.insert(cardID)
        }
        for date in BillingService.partDates(record: record, card: record.e1card) {
            let day = Calendar.current.startOfDay(for: date)
            let paid = snapshot.invoicePaidByKey[
                invoiceKey(cardID: record.e1card?.id, date: day, isPaid: true)
            ] ?? snapshot.invoicePaidByKey[
                invoiceKey(cardID: record.e1card?.id, date: day, isPaid: false)
            ] ?? false
            snapshot.touchedPaymentKeys.insert(paymentKey(bankID: record.e1card?.e8bank?.id, date: day, isPaid: paid))
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
            paymentKeys: snapshot.touchedPaymentKeys,
            context: context
        )
    }

    private static func invoiceKey(cardID: String?, date: Date, isPaid: Bool) -> String {
        let rawCardID = cardID ?? "__no_card__"
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let state = isPaid ? "paid" : "unpaid"
        return "\(rawCardID)#\(day)#\(state)"
    }

    private static func paymentKey(bankID: String?, date: Date, isPaid: Bool) -> String {
        let rawBankID = bankID ?? "__no_bank__"
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let state = isPaid ? "paid" : "unpaid"
        return "\(rawBankID)#\(day)#\(state)"
    }

    private static func recalculateTouchedBilling(
        cardIDs: Set<String>,
        paymentKeys: Set<String>,
        context: ModelContext
    ) {
        let cardDesc = FetchDescriptor<E1card>()
        let paymentDesc = FetchDescriptor<E7payment>()
        let invoiceDesc = FetchDescriptor<E2invoice>()
        let cards = (try? context.fetch(cardDesc)) ?? []
        var payments = (try? context.fetch(paymentDesc)) ?? []
        var invoices = (try? context.fetch(invoiceDesc)) ?? []

        for invoice in invoices where invoice.e6parts.isEmpty {
            if let payment = invoice.e7payment {
                payment.e2invoices.removeAll { $0.id == invoice.id }
            }
            clearInvoiceState(invoice)
            invoice.e7payment = nil
            context.delete(invoice)
        }
        invoices = (try? context.fetch(invoiceDesc)) ?? []
        normalizeInvoices(
            invoices.filter { cardIDs.contains($0.e1card?.id ?? "") },
            context: context
        )

        for card in cards where cardIDs.contains(card.id) {
            recalculateCard(card)
        }

        payments = (try? context.fetch(paymentDesc)) ?? []
        normalizePayments(
            payments.filter { payment in
                let key = paymentKey(bankID: payment.e8bank?.id, date: payment.date, isPaid: payment.isPaid)
                return paymentKeys.contains(key)
            },
            context: context
        )
        payments = (try? context.fetch(paymentDesc)) ?? []
        for payment in payments {
            let key = paymentKey(bankID: payment.e8bank?.id, date: payment.date, isPaid: payment.isPaid)
            if payment.e2invoices.isEmpty {
                clearPaymentState(payment)
                context.delete(payment)
                continue
            }
            if paymentKeys.contains(key) {
                recalculatePayment(payment)
            }
        }
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
            if let ex = card.e2invoices.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: day) && $0.isPaid == (fallbackInvoicePaid ?? fallbackPaymentPaid ?? false)
            }) {
                return ex
            }
            let inv = E2invoice(date: day)
            setInvoiceCard(inv, card: card, isPaid: fallbackInvoicePaid ?? fallbackPaymentPaid ?? false)
            context.insert(inv)
            return inv
        }

        let desc = FetchDescriptor<E2invoice>(
            predicate: #Predicate { $0.date == day && $0.e1paid == nil && $0.e1unpaid == nil }
        )
        if let ex = try? context.fetch(desc).first {
            return ex
        }

        let inv = E2invoice(date: day)
        context.insert(inv)
        return inv
    }

    private static func findOrCreatePayment(
        date: Date,
        bank: E8bank?,
        isPaid: Bool,
        fallbackPaid: Bool?,
        context: ModelContext
    ) -> E7payment {
        let day  = Calendar.current.startOfDay(for: date)
        let desc = FetchDescriptor<E7payment>(predicate: #Predicate { $0.date == day })
        let payments = (try? context.fetch(desc)) ?? []
        if let ex = payments.first(where: {
            // invoice 集計の見かけ状態でなく、所属先そのものを見る
            $0.e8bank?.id == bank?.id && (($0.e8paid != nil) == isPaid)
        }) {
            return ex
        }
        let p = E7payment(date: day)
        setPaymentBank(p, bank: bank, isPaid: bank == nil ? false : (fallbackPaid ?? isPaid))
        context.insert(p)
        return p
    }

    private static func recalculatePayment(_ payment: E7payment) {
        payment.sumAmount = payment.e2invoices.reduce(.zero) { $0 + $1.sumAmount }
        payment.sumNoCheck = payment.e2invoices.reduce(0) { $0 + $1.sumNoCheck }
    }

    private static func normalizeInvoices(_ invoices: [E2invoice], context: ModelContext) {
        var canonicalByKey: [String: E2invoice] = [:]

        for invoice in invoices {
            let key = invoiceKey(cardID: invoice.e1card?.id, date: invoice.date, isPaid: invoice.isPaid)
            if let canonical = canonicalByKey[key] {
                // 同一請求へ part を集約する
                for part in invoice.e6parts {
                    part.e2invoice = canonical
                }
                // 親 payment が無ければ引き継ぐ
                if canonical.e7payment == nil {
                    canonical.e7payment = invoice.e7payment
                }
                clearInvoiceState(invoice)
                invoice.e7payment = nil
                context.delete(invoice)
            } else {
                canonicalByKey[key] = invoice
            }
        }
    }

    private static func normalizePayments(_ payments: [E7payment], context: ModelContext) {
        var canonicalByKey: [String: E7payment] = [:]

        for payment in payments {
            let key = paymentKey(bankID: payment.e8bank?.id, date: payment.date, isPaid: payment.isPaid)
            if let canonical = canonicalByKey[key] {
                // 同一支払へ invoice を集約する
                for invoice in payment.e2invoices {
                    invoice.e7payment = canonical
                }
                clearPaymentState(payment)
                context.delete(payment)
            } else {
                canonicalByKey[key] = payment
            }
        }
    }

    private static func setInvoiceCard(_ invoice: E2invoice, card: E1card?, isPaid: Bool) {
        invoice.e1paid = nil
        invoice.e1unpaid = nil
        guard let card else { return }
        if isPaid {
            invoice.e1paid = card
        } else {
            invoice.e1unpaid = card
        }
    }

    private static func clearInvoiceState(_ invoice: E2invoice) {
        invoice.e1paid = nil
        invoice.e1unpaid = nil
    }

    private static func setInvoiceState(_ invoice: E2invoice, isPaid: Bool) {
        guard let card = invoice.e1card else {
            clearInvoiceState(invoice)
            return
        }
        setInvoiceCard(invoice, card: card, isPaid: isPaid)
    }

    private static func setPaymentBank(_ payment: E7payment, bank: E8bank?, isPaid: Bool) {
        payment.e8paid = nil
        payment.e8unpaid = nil
        guard let bank else { return }
        if isPaid {
            payment.e8paid = bank
        } else {
            payment.e8unpaid = bank
        }
    }

    private static func clearPaymentState(_ payment: E7payment) {
        payment.e8paid = nil
        payment.e8unpaid = nil
    }

    private static func moveInvoice(_ invoice: E2invoice, toPaid: Bool, context: ModelContext) {
        let bank = invoice.e1card?.e8bank
        let oldPayment = invoice.e7payment
        setInvoiceState(invoice, isPaid: toPaid)
        let newPayment = findOrCreatePayment(
            date: invoice.date,
            bank: bank,
            isPaid: toPaid,
            fallbackPaid: toPaid,
            context: context
        )
        invoice.e7payment = newPayment
        // 再利用された payment でも paid/unpaid 所属を正に戻す
        setPaymentBank(newPayment, bank: bank, isPaid: bank == nil ? false : toPaid)
        recalculatePayment(newPayment)
        if let oldPayment, oldPayment.id != newPayment.id {
            recalculatePayment(oldPayment)
            if oldPayment.e2invoices.isEmpty {
                clearPaymentState(oldPayment)
                context.delete(oldPayment)
            }
        }
    }

    private static func commit(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
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
