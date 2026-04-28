import SwiftUI
import Foundation

// MARK: - URL

/// ヘルプドキュメント URL（言語別）
func helpDocURL() -> URL {
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    if lang == "ja" {
        return URL(string: "https://docs.azukid.com/jp/sumpo/PayNote/PayNote.html")!
    }
    return URL(string: "https://docs.azukid.com/en/sumpo/PayNote/PayNote.html")!
}

// MARK: - 入力制約

let APP_MAX_AMOUNT: Decimal = 99_999_999
let APP_MAX_NAME_LEN   = 50
let APP_MAX_NOTE_LEN   = 200
let APP_MAX_PART_COUNT = 99   // 分割払い最大回数

// MARK: - 日付範囲

let APP_MIN_DATE = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!
let APP_MAX_DATE = Calendar.current.date(from: DateComponents(year: 2100, month: 12, day: 31))!

// MARK: - Layout

let COLOR_AMOUNT_POSITIVE: Color = .primary
let COLOR_AMOUNT_NEGATIVE: Color = .red
let COLOR_UNPAID: Color          = Color(.systemOrange)
let COLOR_PAID: Color            = Color(.systemGreen)
let COLOR_SEPARATOR: Color       = Color(.separator)
