import SwiftUI
import SwiftData

struct InvoiceListView: View {
    let payment: E7payment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editRecord: E3record?

    private var includesUnselectedCard: Bool {
        payment.e2invoices.contains { $0.e1card == nil }
    }

    private var bankNameText: String {
        if !payment.hasAnySelectedCard && includesUnselectedCard {
            return NSLocalizedString("payment.card.noSelection", comment: "")
        }
        if let bankName = payment.e8bank?.zName, !bankName.isEmpty {
            return bankName
        }
        return NSLocalizedString("payment.bank.noSelection", comment: "")
    }

    private var statementTitleText: String {
        let dateText = AppDateFormat.singleLineText(payment.date)
        let suffix = NSLocalizedString("invoice.statement.debitSuffix", comment: "")
        return "\(dateText)\(suffix)"
    }

    private var invoices: [E2invoice] {
        payment.e2invoices.sorted {
            ($0.e1card?.zName ?? "") < ($1.e1card?.zName ?? "")
        }
    }

    var body: some View {
        List {
            // 口座名・日付・合計を同一セクションにまとめる
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(bankNameText)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        Text(payment.isPaid ? "payment.status.paidShort" : "payment.status.unpaidShort")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(payment.isPaid
                                ? COLOR_PAID.opacity(0.2)
                                : COLOR_UNPAID.opacity(0.2))
                            .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Text(statementTitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    HStack {
                        Text("label.total")
                        Spacer()
                        Text(payment.sumAmount.currencyString())
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                    }
                }
            }

            // カード別請求
            ForEach(invoices) { invoice in
                Section {
                    ForEach(invoice.e6parts.sorted { $0.nPartNo < $1.nPartNo }) { part in
                        Button {
                            if let record = part.e3record {
                                // 明細セルタップで明細編集シートを開く
                                editRecord = record
                            }
                        } label: {
                            PartRow(part: part)
                        }
                        .buttonStyle(.plain)
                    }

                    // 明細が複数行のときのみ小計を表示する
                    if 1 < invoice.e6parts.count {
                        HStack {
                            Spacer()
                            Text(invoice.sumAmount.currencyString())
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(invoice.isPaid ? COLOR_PAID : COLOR_UNPAID)
                        }
                    }
                } header: {
                    HStack {
                        Text(invoice.e1card?.zName ?? "—")
                    }
                }
            }
        }
        .scalableNavigationTitle("invoice.statement.title")
        .sheet(item: $editRecord) { record in
            NavigationStack {
                RecordEditView(mode: .edit(record)) { bankChanged in
                    // 口座変更時だけ payment 所属が変わり得るため状況一覧へ戻す
                    if bankChanged {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleInvoicePaid(_ invoice: E2invoice) {
        // 決済手段未選択は未払のまま保持する
        if invoice.e1card == nil && !invoice.isPaid {
            return
        }
        try? RecordService.setInvoicePaid(
            invoice,
            isPaid: !invoice.isPaid,
            context: context
        )
    }
}

private extension E7payment {
    var hasAnySelectedCard: Bool {
        // 明細レコード側に決済手段が残っていれば、口座未選択として扱う
        if e2invoices.contains(where: { $0.e1card != nil }) {
            return true
        }
        return e2invoices
            .flatMap(\.e6parts)
            .contains { $0.e3record?.e1card != nil }
    }
}

// MARK: - Part Row

private struct PartRow: View {
    let part: E6part
    private var record: E3record? { part.e3record }

    var body: some View {
        if let record {
            // 引き落とし明細は履歴セルを流用し、状態カプセルだけ非表示にする
            RecordSummaryRow(
                record: record,
                amountOverride: part.nAmount,
                showsStatus: false
            )
        } else {
            HStack {
                Text("—")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(part.nAmount.currencyString())
                    .font(.body.monospacedDigit())
            }
        }
    }
}
