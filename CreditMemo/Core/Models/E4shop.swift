import Foundation
import SwiftData

/// 利用店　　＜＜＜ 2.0.0から E5tag に統合して廃止、DB構造だけが残っている状態
///
/// sortAmount / sortCount は正確な累計値ではなく、並び順の重みとして使う。
/// 保存や繰り返し追加のたびに単純加算し、編集差分や削除では減算しない。
/// 値が十分大きくなった将来は、順序を保ったままリセットする機能を追加する前提。
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
