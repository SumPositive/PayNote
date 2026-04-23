import Foundation
import SwiftData

/// 利用店
@Model
final class E4shop {
    @Attribute(.unique) var id: String
    var zName: String
    var zNote: String
    var sortAmount: Decimal
    var sortCount: Int32
    var sortDate: Date?
    var sortName: String

    @Relationship(deleteRule: .nullify) var e3records: [E3record]

    init(
        id: String = UUID().uuidString,
        zName: String = "",
        zNote: String = "",
        sortAmount: Decimal = 0,
        sortCount: Int32 = 0,
        sortDate: Date? = nil,
        sortName: String = ""
    ) {
        self.id = id
        self.zName = zName
        self.zNote = zNote
        self.sortAmount = sortAmount
        self.sortCount = sortCount
        self.sortDate = sortDate
        self.sortName = sortName
        self.e3records = []
    }
}
