import Foundation
import SwiftData

/// 支払（月別）
/// - date: 旧 nYearMMDD(Int32 YYYYMMDD形式) から Date に変換
/// - 旧方式に合わせ、paid/unpaid の所属で状態を表す
/// - ただし新仕様では「日付 + 口座」単位で1件を持つ
@Model
final class E7payment {
    @Attribute(.unique) var id: String
    var date: Date
    var sumAmount: Decimal
    var sumNoCheck: Int16

    var e8paid: E8bank?
    var e8unpaid: E8bank?
    @Relationship(deleteRule: .cascade) var e2invoices: [E2invoice]

    var e8bank: E8bank? { e8paid ?? e8unpaid }

    /// 物理フィールド（e8paid != nil）による支払済み判定。
    /// findOrCreatePayment / normalizePayments など内部処理ではこちらを使う。
    var isPaidPhysical: Bool { e8paid != nil }

    /// UI 表示用: 口座未選択でも状態を返せるよう配下 invoice から計算する。
    /// 注意: 口座なし（e8paid/e8unpaid 共に nil）の場合は e8paid != nil と乖離しうる。
    /// 内部処理での payment キー構築には isPaidPhysical を使うこと。
    var isPaid: Bool {
        !e2invoices.isEmpty && e2invoices.allSatisfy(\.isPaid)
    }

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        sumAmount: Decimal = 0,
        sumNoCheck: Int16 = 0
    ) {
        self.id = id
        self.date = date
        self.sumAmount = sumAmount
        self.sumNoCheck = sumNoCheck
        self.e2invoices = []
    }
}
