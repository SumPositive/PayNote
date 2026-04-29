import Foundation
import SwiftData

/// JSON インポート
///
/// - 既存データは削除せず、id 単位で追記・更新する
/// - 配列キーは省略可能とし、マスタのみ・一部データのみの JSON も受け入れる
/// - 請求/支払は E6part を持たないため、record から再構築した後に状態だけを反映する
@MainActor
enum JSONImport {

    struct ImportData: Decodable {
        var exportDate: Date?
        var banks: [BankData]?
        var cards: [CardData]?
        var shops: [ShopData]?
        var categories: [CategoryData]?
        var records: [RecordData]?
        var invoices: [InvoiceData]?
        var payments: [PaymentData]?
    }

    struct BankData: Decodable {
        var id: String
        var name: String
        var note: String
        var row: Int
    }

    struct CardData: Decodable {
        var id: String
        var name: String
        var note: String
        var row: Int
        var closingDay: Int
        var payDay: Int
        var payMonth: Int
        var bonus1: Int
        var bonus2: Int
        var billingType: Int
        var offsetDays: Int?
        var bankID: String?

        enum CodingKeys: String, CodingKey {
            case id, name, note, row, closingDay, payDay, payMonth, bonus1, bonus2, billingType, offsetDays, bankID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 0
            closingDay = try c.decodeIfPresent(Int.self, forKey: .closingDay) ?? 20
            payDay = try c.decodeIfPresent(Int.self, forKey: .payDay) ?? 27
            payMonth = try c.decodeIfPresent(Int.self, forKey: .payMonth) ?? 1
            bonus1 = try c.decodeIfPresent(Int.self, forKey: .bonus1) ?? 0
            bonus2 = try c.decodeIfPresent(Int.self, forKey: .bonus2) ?? 0
            // 旧JSONは請求方式を持たないため cardCycle を既定にする
            billingType = try c.decodeIfPresent(Int.self, forKey: .billingType) ?? Int(BillingType.cardCycle.rawValue)
            offsetDays = try c.decodeIfPresent(Int.self, forKey: .offsetDays)
            bankID = try c.decodeIfPresent(String.self, forKey: .bankID)
        }
    }

    struct ShopData: Decodable {
        var id: String
        var name: String
        var note: String
    }

    struct CategoryData: Decodable {
        var id: String
        var name: String
        var note: String
    }

    struct RecordData: Decodable {
        var id: String
        var dateUse: Date
        var name: String
        var note: String
        var amount: String
        var payType: Int
        var repeatMonths: Int
        var cardID: String?
        var shopID: String?
        var categoryID: String?
        var categoryIDs: [String]?
    }

    struct InvoiceData: Decodable {
        var id: String
        var date: Date
        var isPaid: Bool
        var cardID: String?
        var paymentID: String?
    }

    struct PaymentData: Decodable {
        var id: String
        var date: Date
        var bankID: String?
        var sumAmount: String?
        var sumNoCheck: Int?
        var isPaid: Bool
    }

    enum Phase {
        case readingFile
        case decoding
        case importingMasters
        case importingRecords
        case rebuildingBilling
        case applyingStates
        case saving

        /// インポート進行テキスト（ja/en）
        func message(locale: Locale) -> String {
            let isJapanese = locale.language.languageCode?.identifier == "ja"
            switch self {
            case .readingFile:
                return isJapanese ? "JSONファイルを読み込み中…" : "Reading JSON file..."
            case .decoding:
                return isJapanese ? "JSONを解析中…" : "Decoding JSON..."
            case .importingMasters:
                return isJapanese ? "マスタデータを取り込み中…" : "Importing master data..."
            case .importingRecords:
                return isJapanese ? "決済履歴を取り込み中…" : "Importing records..."
            case .rebuildingBilling:
                return isJapanese ? "請求データを再構築中…" : "Rebuilding billing..."
            case .applyingStates:
                return isJapanese ? "未払/済み状態を反映中…" : "Applying paid states..."
            case .saving:
                return isJapanese ? "保存中…" : "Saving..."
            }
        }
    }

    struct Result {
        var bankCount: Int
        var cardCount: Int
        var shopCount: Int
        var categoryCount: Int
        var recordCount: Int
        var invoiceStateCount: Int
        var paymentStateCount: Int
    }

    static func importData(
        from url: URL,
        context: ModelContext,
        onPhase: ((Phase) -> Void)? = nil
    ) async throws -> Result {
        onPhase?(.readingFile)
        await Task.yield()
        let data = try Data(contentsOf: url)

        onPhase?(.decoding)
        await Task.yield()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ImportData.self, from: data)

        let banks = (try? context.fetch(FetchDescriptor<E8bank>())) ?? []
        let cards = (try? context.fetch(FetchDescriptor<E1card>())) ?? []
        let shops = (try? context.fetch(FetchDescriptor<E4shop>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<E5category>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<E3record>())) ?? []

        var bankByID = Dictionary(uniqueKeysWithValues: banks.map { ($0.id, $0) })
        var cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var shopByID = Dictionary(uniqueKeysWithValues: shops.map { ($0.id, $0) })
        var categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        onPhase?(.importingMasters)
        await Task.yield()
        let importedBankCount = importBanks(payload.banks ?? [], bankByID: &bankByID, context: context)
        let importedCardCount = importCards(payload.cards ?? [], cardByID: &cardByID, bankByID: bankByID, context: context)
        let importedShopCount = importShops(payload.shops ?? [], shopByID: &shopByID, context: context)
        let importedCategoryCount = importCategories(payload.categories ?? [], categoryByID: &categoryByID, context: context)

        onPhase?(.importingRecords)
        await Task.yield()
        let importedRecordCount = importRecords(
            payload.records ?? [],
            recordByID: &recordByID,
            cardByID: cardByID,
            shopByID: shopByID,
            categoryByID: categoryByID,
            context: context
        )

        // record が入った場合や、状態 JSON を反映する場合は請求を正規状態へ作り直す
        if 0 < importedRecordCount || payload.invoices != nil || payload.payments != nil {
            onPhase?(.rebuildingBilling)
            await Task.yield()
            RecordService.rebuildBilling(context: context)
        }

        onPhase?(.applyingStates)
        await Task.yield()
        let appliedInvoiceStateCount = applyInvoiceStates(payload.invoices ?? [], context: context)
        let appliedPaymentStateCount = applyPaymentStates(payload.payments ?? [], context: context)
        RecordService.cleanupOrphanBilling(context: context)

        onPhase?(.saving)
        await Task.yield()
        if context.hasChanges {
            try context.save()
        }

        return Result(
            bankCount: importedBankCount,
            cardCount: importedCardCount,
            shopCount: importedShopCount,
            categoryCount: importedCategoryCount,
            recordCount: importedRecordCount,
            invoiceStateCount: appliedInvoiceStateCount,
            paymentStateCount: appliedPaymentStateCount
        )
    }

    private static func importBanks(
        _ items: [BankData],
        bankByID: inout [String: E8bank],
        context: ModelContext
    ) -> Int {
        for item in items {
            let bank = bankByID[item.id] ?? {
                let value = E8bank(id: item.id)
                context.insert(value)
                bankByID[item.id] = value
                return value
            }()
            // 口座マスタの基本項目を上書きする
            bank.zName = item.name
            bank.zNote = item.note
            bank.nRow = Int32(item.row)
        }
        return items.count
    }

    private static func importCards(
        _ items: [CardData],
        cardByID: inout [String: E1card],
        bankByID: [String: E8bank],
        context: ModelContext
    ) -> Int {
        for item in items {
            let card = cardByID[item.id] ?? {
                let value = E1card(id: item.id)
                context.insert(value)
                cardByID[item.id] = value
                return value
            }()
            // 決済手段マスタの基本項目を上書きする
            card.zName = item.name
            card.zNote = item.note
            card.nRow = Int32(item.row)
            card.nClosingDay = Int16(item.closingDay)
            card.nPayDay = Int16(item.payDay)
            card.nPayMonth = Int16(item.payMonth)
            card.nBonus1 = Int16(item.bonus1)
            card.nBonus2 = Int16(item.bonus2)
            card.nBillingType = Int16(item.billingType)
            if let offset = item.offsetDays, 0 < offset {
                card.nOffsetDays = Int16(offset)
            } else {
                card.nOffsetDays = nil
            }
            card.e8bank = item.bankID.flatMap { bankByID[$0] }
        }
        return items.count
    }

    private static func importShops(
        _ items: [ShopData],
        shopByID: inout [String: E4shop],
        context: ModelContext
    ) -> Int {
        for item in items {
            let shop = shopByID[item.id] ?? {
                let value = E4shop(id: item.id)
                context.insert(value)
                shopByID[item.id] = value
                return value
            }()
            // 利用店マスタの基本項目を上書きする
            shop.zName = item.name
            shop.zNote = item.note
            shop.sortName = item.name
        }
        return items.count
    }

    private static func importCategories(
        _ items: [CategoryData],
        categoryByID: inout [String: E5category],
        context: ModelContext
    ) -> Int {
        for item in items {
            let category = categoryByID[item.id] ?? {
                let value = E5category(id: item.id)
                context.insert(value)
                categoryByID[item.id] = value
                return value
            }()
            // タグマスタの基本項目を上書きする
            category.zName = item.name
            category.zNote = item.note
            category.sortName = item.name
        }
        return items.count
    }

    private static func importRecords(
        _ items: [RecordData],
        recordByID: inout [String: E3record],
        cardByID: [String: E1card],
        shopByID: [String: E4shop],
        categoryByID: [String: E5category],
        context: ModelContext
    ) -> Int {
        for item in items {
            let record = recordByID[item.id] ?? {
                let value = E3record(id: item.id)
                context.insert(value)
                recordByID[item.id] = value
                return value
            }()

            // 明細の正本を id 単位で更新する
            record.dateUse = item.dateUse
            record.zName = item.name
            record.zNote = item.note
            record.nAmount = decimalValue(item.amount)
            record.nPayType = Int16(item.payType)
            record.nRepeat = Int16(item.repeatMonths)
            record.e1card = item.cardID.flatMap { cardByID[$0] }
            record.e4shop = item.shopID.flatMap { shopByID[$0] }

            let multiCategories = (item.categoryIDs ?? [])
                .compactMap { categoryByID[$0] }
            if multiCategories.isEmpty {
                let singleCategory = item.categoryID.flatMap { categoryByID[$0] }
                record.e5category = singleCategory
                record.e5categories = singleCategory.map { [$0] } ?? []
            } else {
                record.e5category = multiCategories.first
                record.e5categories = multiCategories
            }
        }
        return items.count
    }

    private static func applyInvoiceStates(
        _ items: [InvoiceData],
        context: ModelContext
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        let invoices = (try? context.fetch(FetchDescriptor<E2invoice>())) ?? []
        let invoiceGroups = Dictionary(grouping: invoices) {
            invoiceKey(cardID: $0.e1card?.id, date: $0.date)
        }

        var updatedCount = 0
        for item in items {
            let key = invoiceKey(cardID: item.cardID, date: item.date)
            let targetInvoices = (invoiceGroups[key] ?? []).filter { $0.isPaid != item.isPaid }
            for invoice in targetInvoices {
                moveInvoice(invoice, toPaid: item.isPaid, context: context)
                updatedCount += 1
            }
        }
        return updatedCount
    }

    private static func applyPaymentStates(
        _ items: [PaymentData],
        context: ModelContext
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        let payments = (try? context.fetch(FetchDescriptor<E7payment>())) ?? []
        let paymentGroups = Dictionary(grouping: payments) {
            paymentKey(bankID: $0.e8bank?.id, date: $0.date)
        }

        var updatedCount = 0
        for item in items {
            let key = paymentKey(bankID: item.bankID, date: item.date)
            let targetInvoices = (paymentGroups[key] ?? [])
                .flatMap(\.e2invoices)
                .filter { $0.isPaid != item.isPaid }
            guard !targetInvoices.isEmpty else { continue }
            for invoice in targetInvoices {
                moveInvoice(invoice, toPaid: item.isPaid, context: context)
                updatedCount += 1
            }
        }
        return updatedCount
    }

    private static func invoiceKey(cardID: String?, date: Date) -> String {
        let rawCardID = cardID ?? "__no_card__"
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(rawCardID)#\(day)"
    }

    private static func paymentKey(bankID: String?, date: Date) -> String {
        let rawBankID = bankID ?? "__no_bank__"
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(rawBankID)#\(day)"
    }

    private static func decimalValue(_ rawValue: String) -> Decimal {
        Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func moveInvoice(_ invoice: E2invoice, toPaid: Bool, context: ModelContext) {
        let bank = invoice.e1card?.e8bank
        let oldPayment = invoice.e7payment
        setInvoiceState(invoice, isPaid: toPaid)
        let newPayment = findOrCreatePayment(
            date: invoice.date,
            bank: bank,
            isPaid: toPaid,
            context: context
        )
        invoice.e7payment = newPayment
        recalculatePayment(newPayment)
        if let oldPayment, oldPayment.id != newPayment.id {
            recalculatePayment(oldPayment)
            if oldPayment.e2invoices.isEmpty {
                clearPaymentState(oldPayment)
                context.delete(oldPayment)
            }
        }
    }

    private static func findOrCreatePayment(
        date: Date,
        bank: E8bank?,
        isPaid: Bool,
        context: ModelContext
    ) -> E7payment {
        let day = Calendar.current.startOfDay(for: date)
        let desc = FetchDescriptor<E7payment>(predicate: #Predicate { $0.date == day })
        let payments = (try? context.fetch(desc)) ?? []
        if let payment = payments.first(where: { $0.e8bank?.id == bank?.id && $0.isPaid == isPaid }) {
            return payment
        }
        let payment = E7payment(date: day)
        setPaymentBank(payment, bank: bank, isPaid: bank != nil && isPaid)
        context.insert(payment)
        return payment
    }

    private static func setInvoiceState(_ invoice: E2invoice, isPaid: Bool) {
        invoice.e1paid = nil
        invoice.e1unpaid = nil
        guard let card = invoice.e1card else { return }
        if isPaid {
            invoice.e1paid = card
            return
        }
        invoice.e1unpaid = card
    }

    private static func setPaymentBank(_ payment: E7payment, bank: E8bank?, isPaid: Bool) {
        payment.e8paid = nil
        payment.e8unpaid = nil
        guard let bank else { return }
        if isPaid {
            payment.e8paid = bank
            return
        }
        payment.e8unpaid = bank
    }

    private static func clearPaymentState(_ payment: E7payment) {
        payment.e8paid = nil
        payment.e8unpaid = nil
    }

    private static func recalculatePayment(_ payment: E7payment) {
        payment.sumAmount = payment.e2invoices.reduce(.zero) { $0 + $1.sumAmount }
        payment.sumNoCheck = payment.e2invoices.reduce(0) { $0 + $1.sumNoCheck }
    }
}
