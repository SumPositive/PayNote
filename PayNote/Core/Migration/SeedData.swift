import Foundation
import SwiftData

@MainActor
enum SeedData {
    struct CardPreset {
        var name: String
        var closingDay: Int16
        var payDay: Int16
        var payMonth: Int16
    }

    struct BankPreset {
        var name: String
    }

    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<E1card>())) ?? 0
        guard count == 0 else { return }
        let bankPresets = localizedBankPresets()
        let cardPresets = localizedCardPresets()

        // 引き落とし口座プリセット
        for (row, b) in bankPresets.enumerated() {
            let bank = E8bank(
                zName: b.name,
                nRow: Int32(row)
            )
            context.insert(bank)
        }

        // 決済方法プリセット
        for (row, p) in cardPresets.enumerated() {
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
    static func presetsForCurrentLocale() -> [CardPreset] {
        localizedCardPresets()
    }

    /// 現在の表示言語に合わせた口座プリセット一覧を返す
    static func bankPresetsForCurrentLocale() -> [BankPreset] {
        localizedBankPresets()
    }

    // MARK: - Private

    /// 言語ごとに初期プリセットを切り替える
    private static func localizedCardPresets() -> [CardPreset] {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        if lang == "ja" {
            return japaneseCardPresets()
        }
        return westernCardPresets()
    }

    /// 言語ごとに口座プリセットを切り替える
    private static func localizedBankPresets() -> [BankPreset] {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        if lang == "ja" {
            return japaneseBankPresets()
        }
        return westernBankPresets()
    }

    /// 日本向けの代表的な決済方法
    private static func japaneseCardPresets() -> [CardPreset] {
        [
            CardPreset(name: "楽天カード", closingDay: 29, payDay: 27, payMonth: 1),
            CardPreset(name: "PayPayカード", closingDay: 29, payDay: 27, payMonth: 1),
            CardPreset(name: "dカード", closingDay: 15, payDay: 10, payMonth: 1),
            CardPreset(name: "三井住友カード", closingDay: 15, payDay: 10, payMonth: 1),
            CardPreset(name: "イオンカード", closingDay: 10, payDay: 2, payMonth: 1),
            CardPreset(name: "Suica（クレジットでチャージ）", closingDay: 29, payDay: 27, payMonth: 1),
            CardPreset(name: "nanaco", closingDay: 29, payDay: 27, payMonth: 1),
            CardPreset(name: "WAON", closingDay: 29, payDay: 27, payMonth: 1),
            CardPreset(name: "PayPay（クレジットでチャージ）", closingDay: 29, payDay: 27, payMonth: 1),
            CardPreset(name: "楽天Pay（クレジットでチャージ）", closingDay: 29, payDay: 27, payMonth: 1),
        ]
    }

    /// 英語環境では欧米の代表的な決済方法を初期表示する
    private static func westernCardPresets() -> [CardPreset] {
        [
            CardPreset(name: "Visa", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Mastercard", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "American Express", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Apple Pay (Card Charge)", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Google Pay (Card Charge)", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "PayPal (Card Charge)", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Venmo (Card Charge)", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Cash App (Card Charge)", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Revolut (Card Charge)", closingDay: 27, payDay: 27, payMonth: 1),
            CardPreset(name: "Klarna", closingDay: 27, payDay: 27, payMonth: 1),
        ]
    }

    /// 日本の主要口座プリセット（引き落とし設定向け）
    private static func japaneseBankPresets() -> [BankPreset] {
        [
            BankPreset(name: "三菱UFJ銀行"),
            BankPreset(name: "三井住友銀行"),
            BankPreset(name: "みずほ銀行"),
            BankPreset(name: "ゆうちょ銀行"),
            BankPreset(name: "りそな銀行"),
            BankPreset(name: "埼玉りそな銀行"),
            BankPreset(name: "楽天銀行"),
            BankPreset(name: "住信SBIネット銀行"),
            BankPreset(name: "PayPay銀行"),
            BankPreset(name: "ソニー銀行"),
        ]
    }

    /// 欧米の主要口座プリセット（引き落とし設定向け）
    private static func westernBankPresets() -> [BankPreset] {
        [
            BankPreset(name: "JPMorgan Chase"),
            BankPreset(name: "Bank of America"),
            BankPreset(name: "Citibank"),
            BankPreset(name: "Wells Fargo"),
            BankPreset(name: "HSBC"),
            BankPreset(name: "Barclays"),
            BankPreset(name: "Lloyds Bank"),
            BankPreset(name: "Santander"),
            BankPreset(name: "BNP Paribas"),
            BankPreset(name: "Deutsche Bank"),
        ]
    }
}
