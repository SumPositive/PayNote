import Foundation
import SwiftData

/// 支払（月別）
/// - date: 旧 nYearMMDD(Int32 YYYYMMDD形式) から Date に変換
/// - isPaid: 旧 E0root の e7paids/e7unpaids 二系統を Bool に置き換え
@Model
final class E7payment {
    @Attribute(.unique) var id: String
    var date: Date
    var sumAmount: Decimal
    var sumNoCheck: Int16
    var isPaid: Bool

    @Relationship(deleteRule: .cascade) var e2invoices: [E2invoice]

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        sumAmount: Decimal = 0,
        sumNoCheck: Int16 = 0,
        isPaid: Bool = false
    ) {
        self.id = id
        self.date = date
        self.sumAmount = sumAmount
        self.sumNoCheck = sumNoCheck
        self.isPaid = isPaid
        self.e2invoices = []
    }
}
