import Foundation
import SwiftData

@MainActor
enum SeedData {
    struct Preset {
        var name: String
        var closingDay: Int16
        var payDay: Int16
        var payMonth: Int16
    }

    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<E1card>())) ?? 0
        guard count == 0 else { return }
        let presets = localizedPresets()

        for (row, p) in presets.enumerated() {
            let card = E1card(
                zName: p.name,
                nRow: Int32(row),
                nClosingDay: p.closingDay,
                nPayDay: p.payDay,
                nPayMonth: p.payMonth
            )
            context.insert(card)
        }
        try? context.save()
    }

    /// 現在の表示言語に合わせたプリセット一覧を返す
    static func presetsForCurrentLocale() -> [Preset] {
        localizedPresets()
    }

    // MARK: - Private

    /// 言語ごとに初期プリセットを切り替える
    private static func localizedPresets() -> [Preset] {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        if lang == "ja" {
            return japanesePresets()
        }
        return westernPresets()
    }

    /// 日本向けの代表的な決済方法
    private static func japanesePresets() -> [Preset] {
        [
            Preset(name: "楽天カード", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "PayPayカード", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "dカード", closingDay: 15, payDay: 10, payMonth: 1),
            Preset(name: "三井住友カード", closingDay: 15, payDay: 10, payMonth: 1),
            Preset(name: "イオンカード", closingDay: 10, payDay: 2, payMonth: 1),
            Preset(name: "Suica（クレジットでチャージ）", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "nanaco", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "WAON", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "PayPay（クレジットでチャージ）", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "楽天Pay（クレジットでチャージ）", closingDay: 29, payDay: 27, payMonth: 1),
        ]
    }

    /// 英語環境では欧米の代表的な決済方法を初期表示する
    private static func westernPresets() -> [Preset] {
        [
            Preset(name: "Visa", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Mastercard", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "American Express", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Apple Pay (Card Charge)", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Google Pay (Card Charge)", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "PayPal (Card Charge)", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Venmo (Card Charge)", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Cash App (Card Charge)", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Revolut (Card Charge)", closingDay: 29, payDay: 27, payMonth: 1),
            Preset(name: "Klarna", closingDay: 29, payDay: 27, payMonth: 1),
        ]
    }
}
