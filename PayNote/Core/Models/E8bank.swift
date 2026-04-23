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
    }
}
