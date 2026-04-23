import Foundation
import SwiftData

/// 請求書（カード・月別）
/// - date: 旧 nYearMMDD(Int32 YYYYMMDD形式) から Date に変換
/// - isPaid: 旧 e1paid/e1unpaid 二系統リレーションを Bool + 単一リレーションに置き換え
@Model
final class E2invoice {
    @Attribute(.unique) var id: String
    var date: Date
    var isPaid: Bool

    var e1card: E1card?
    var e7payment: E7payment?
    @Relationship(deleteRule: .cascade) var e6parts: [E6part]

    // 分割明細の集計（都度計算）
    var sumAmount: Decimal { e6parts.reduce(.zero) { $0 + $1.nAmount } }
    var sumNoCheck: Int16  { Int16(e6parts.filter { $0.nNoCheck != 0 }.count) }

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        isPaid: Bool = false
    ) {
        self.id = id
        self.date = date
        self.isPaid = isPaid
        self.e6parts = []
    }
}
