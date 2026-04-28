import Foundation
import SwiftData

@MainActor
enum JSONExport {

    struct ExportData: Codable {
        var exportDate: Date
        var banks: [BankData]
        var cards: [CardData]
        var shops: [ShopData]
        var categories: [CategoryData]
        var records: [RecordData]
        var invoices: [InvoiceData]
        var payments: [PaymentData]
    }

    struct BankData: Codable {
        var id, name, note: String; var row: Int
    }

    struct CardData: Codable {
        var id, name, note: String
        var row, closingDay, payDay, payMonth, bonus1, bonus2: Int
        var bankID: String?
    }

    struct ShopData: Codable {
        var id, name, note: String
    }

    struct CategoryData: Codable {
        var id, name, note: String
    }

    struct RecordData: Codable {
        var id: String
        var dateUse: Date
        var name, note, amount: String
        var payType, repeatMonths: Int
        var cardID, shopID, categoryID: String?
        var categoryIDs: [String]
    }

    struct InvoiceData: Codable {
        var id: String
        var date: Date
        var isPaid: Bool
        var cardID: String?
        var paymentID: String?
    }

    struct PaymentData: Codable {
        var id: String
        var date: Date
        var bankID: String?
        var sumAmount: String
        var sumNoCheck: Int
        var isPaid: Bool
    }

    enum Phase {
        case readingBanks
        case readingCards
        case readingShops
        case readingCategories
        case readingRecords
        case encoding

        /// エクスポート進行テキスト（ja/en）
        func message(locale: Locale) -> String {
            let isJapanese = locale.language.languageCode?.identifier == "ja"
            switch self {
            case .readingBanks:
                return isJapanese ? "口座データを読み込み中…" : "Reading accounts..."
            case .readingCards:
                return isJapanese ? "決済手段を読み込み中…" : "Reading payment methods..."
            case .readingShops:
                return isJapanese ? "店舗データを読み込み中…" : "Reading shops..."
            case .readingCategories:
                return isJapanese ? "タグデータを読み込み中…" : "Reading tags..."
            case .readingRecords:
                return isJapanese ? "決済履歴を読み込み中…" : "Reading records..."
            case .encoding:
                return isJapanese ? "JSONを生成中…" : "Generating JSON..."
            }
        }
    }

    static func exportData(
        context: ModelContext,
        onPhase: ((Phase) -> Void)? = nil
    ) async throws -> Data {
        // 画面へ進行表示を出せるように、工程ごとに通知する
        onPhase?(.readingBanks)
        await Task.yield()
        let banks      = (try? context.fetch(FetchDescriptor<E8bank>())) ?? []
        onPhase?(.readingCards)
        await Task.yield()
        let cards      = (try? context.fetch(FetchDescriptor<E1card>(sortBy: [SortDescriptor(\E1card.nRow)]))) ?? []
        onPhase?(.readingShops)
        await Task.yield()
        let shops      = (try? context.fetch(FetchDescriptor<E4shop>())) ?? []
        onPhase?(.readingCategories)
        await Task.yield()
        let categories = (try? context.fetch(FetchDescriptor<E5category>())) ?? []
        onPhase?(.readingRecords)
        await Task.yield()
        let records    = (try? context.fetch(FetchDescriptor<E3record>(sortBy: [SortDescriptor(\E3record.dateUse)]))) ?? []
        let invoices   = (try? context.fetch(FetchDescriptor<E2invoice>(sortBy: [SortDescriptor(\E2invoice.date)]))) ?? []
        let payments   = (try? context.fetch(FetchDescriptor<E7payment>(sortBy: [SortDescriptor(\E7payment.date)]))) ?? []

        let bankData     = banks.map      { BankData(id: $0.id, name: $0.zName, note: $0.zNote, row: Int($0.nRow)) }
        let cardData     = cards.map      { c in
            CardData(
                id: c.id,
                name: c.zName,
                note: c.zNote,
                row: Int(c.nRow),
                closingDay: Int(c.nClosingDay),
                payDay: Int(c.nPayDay),
                payMonth: Int(c.nPayMonth),
                bonus1: Int(c.nBonus1),
                bonus2: Int(c.nBonus2),
                bankID: c.e8bank?.id
            )
        }
        let shopData     = shops.map      { ShopData(id: $0.id, name: $0.zName, note: $0.zNote) }
        let categoryData = categories.map { CategoryData(id: $0.id, name: $0.zName, note: $0.zNote) }
        let recordData   = records.map    { r in
            RecordData(
                id: r.id,
                dateUse: r.dateUse,
                name: r.zName,
                note: r.zNote,
                amount: "\(r.nAmount)",
                payType: Int(r.nPayType),
                repeatMonths: Int(r.nRepeat),
                cardID: r.e1card?.id,
                shopID: r.e4shop?.id,
                categoryID: r.e5category?.id,
                categoryIDs: r.e5categories.map(\.id)
            )
        }
        let invoiceData  = invoices.map   { i in InvoiceData(id: i.id, date: i.date, isPaid: i.isPaid, cardID: i.e1card?.id, paymentID: i.e7payment?.id) }
        let paymentData  = payments.map   {
            PaymentData(
                id: $0.id,
                date: $0.date,
                bankID: $0.e8bank?.id,
                sumAmount: "\($0.sumAmount)",
                sumNoCheck: Int($0.sumNoCheck),
                isPaid: $0.isPaid
            )
        }

        let data = ExportData(
            exportDate: Date(),
            banks: bankData,
            cards: cardData,
            shops: shopData,
            categories: categoryData,
            records: recordData,
            invoices: invoiceData,
            payments: paymentData
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        onPhase?(.encoding)
        await Task.yield()
        return try encoder.encode(data)
    }
}
