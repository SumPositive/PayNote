import Foundation

/// 引き落とし状況で使う、日付+表示分類ごとの仮想グループ
struct PaymentDisplayGroup: Identifiable {
    enum Kind: Hashable {
        case unselectedCard
        case unselectedBank
        case bank(id: String, name: String)
    }

    let payment: E7payment
    let kind: Kind
    let invoices: [E2invoice]

    var id: String {
        "\(payment.id)#\(kind.rawValue)"
    }

    var isPaid: Bool {
        invoices.allSatisfy(\.isPaid)
    }

    var sumAmount: Decimal {
        invoices.reduce(.zero) { $0 + $1.sumAmount }
    }

    var includesUnselectedCard: Bool {
        kind == .unselectedCard
    }

    var bankNameText: String {
        switch kind {
        case .unselectedCard:
            let cardLabel = NSLocalizedString("record.field.card", comment: "")
            let noSelection = NSLocalizedString("label.noSelection", comment: "")
            return "\(cardLabel) \(noSelection)"
        case .unselectedBank:
            return NSLocalizedString("payment.bank.noSelection", comment: "")
        case .bank(_, let name):
            return name
        }
    }
}

private extension PaymentDisplayGroup.Kind {
    var rawValue: String {
        switch self {
        case .unselectedCard:
            return "unselected-card"
        case .unselectedBank:
            return "unselected-bank"
        case .bank(let bankID, _):
            return "bank-\(bankID)"
        }
    }
}

extension E7payment {
    /// 同じ支払日の請求を、決済手段未選択 / 口座未選択 / 口座別 に分ける
    var displayGroups: [PaymentDisplayGroup] {
        var buckets: [PaymentDisplayGroup.Kind: [E2invoice]] = [:]

        for invoice in e2invoices {
            let kind: PaymentDisplayGroup.Kind
            if invoice.e1card == nil {
                kind = .unselectedCard
            } else if let bank = invoice.e1card?.e8bank {
                kind = .bank(id: bank.id, name: bank.zName)
            } else {
                kind = .unselectedBank
            }
            buckets[kind, default: []].append(invoice)
        }

        return buckets
            .map { kind, invoices in
                PaymentDisplayGroup(payment: self, kind: kind, invoices: invoices)
            }
            .sorted { lhs, rhs in
                if lhs.payment.date == rhs.payment.date {
                    return lhs.bankNameText.localizedStandardCompare(rhs.bankNameText) == .orderedAscending
                }
                return rhs.payment.date < lhs.payment.date
            }
    }
}
