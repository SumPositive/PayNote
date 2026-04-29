import Foundation
import SwiftData

/// 銀行・口座
@Model
final class E8bank {
    @Attribute(.unique) var id: String
    var zName: String
    var zNote: String
    var nRow: Int32

    @Relationship(deleteRule: .nullify) var e1cards: [E1card]
    @Relationship(deleteRule: .nullify) var e7paids: [E7payment]
    @Relationship(deleteRule: .nullify) var e7unpaids: [E7payment]

    // 互換参照用に支払全体を返す
    var e7payments: [E7payment] { e7paids + e7unpaids }

    init(
        id: String = UUID().uuidString,
        zName: String = "",
        zNote: String = "",
        nRow: Int32 = 0
    ) {
        self.id = id
        self.zName = zName
        self.zNote = zNote
        self.nRow = nRow
        self.e1cards = []
        self.e7paids = []
        self.e7unpaids = []
    }
}
