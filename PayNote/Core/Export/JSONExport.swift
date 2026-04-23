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
    }

    static func exportData(context: ModelContext) throws -> Data {
        let banks      = (try? context.fetch(FetchDescriptor<E8bank>())) ?? []
        let cards      = (try? context.fetch(FetchDescriptor<E1card>(sortBy: [SortDescriptor(\E1card.nRow)]))) ?? []
        let shops      = (try? context.fetch(FetchDescriptor<E4shop>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<E5category>())) ?? []
        let records    = (try? context.fetch(FetchDescriptor<E3record>(sortBy: [SortDescriptor(\E3record.dateUse)]))) ?? []

        let bankData     = banks.map      { BankData(id: $0.id, name: $0.zName, note: $0.zNote, row: Int($0.nRow)) }
        let cardData     = cards.map      { c in CardData(id: c.id, name: c.zName, note: c.zNote, row: Int(c.nRow), closingDay: Int(c.nClosingDay), payDay: Int(c.nPayDay), payMonth: Int(c.nPayMonth), bonus1: Int(c.nBonus1), bonus2: Int(c.nBonus2), bankID: c.e8bank?.id) }
        let shopData     = shops.map      { ShopData(id: $0.id, name: $0.zName, note: $0.zNote) }
        let categoryData = categories.map { CategoryData(id: $0.id, name: $0.zName, note: $0.zNote) }
        let recordData   = records.map    { r in RecordData(id: r.id, dateUse: r.dateUse, name: r.zName, note: r.zNote, amount: "\(r.nAmount)", payType: Int(r.nPayType), repeatMonths: Int(r.nRepeat), cardID: r.e1card?.id, shopID: r.e4shop?.id, categoryID: r.e5category?.id) }

        let data = ExportData(exportDate: Date(), banks: bankData, cards: cardData, shops: shopData, categories: categoryData, records: recordData)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
}
