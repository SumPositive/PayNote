import SwiftUI
import SwiftData

struct InvoiceListView: View {
    let payment: E7payment

    @Environment(\.modelContext) private var context
    @State private var editRecord: E3record?

    private var bankNameText: String {
        let names = Array(
            Set(
                payment.e2invoices
                    .compactMap { $0.e1card?.e8bank?.zName }
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        if names.isEmpty {
            return NSLocalizedString("label.noSelection", comment: "")
        }
        if names.count == 1 {
            return names[0]
        }
        return NSLocalizedString("invoice.bank.multiple", comment: "")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(bankNameText)
                        .font(.headline)
                    Text(statementTitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    ZStack {
                        // 口座合計セルの中央に未払/済みを表示する
                        Text(payment.isPaid ? "payment.status.paidShort" : "payment.status.unpaidShort")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(payment.isPaid
                                ? COLOR_PAID.opacity(0.2)
                                : COLOR_UNPAID.opacity(0.2))
                            .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                            .clipShape(Capsule())

                        HStack {
                            Text("label.total")
                            Spacer()
                            Text(payment.sumAmount.currencyString())
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                        }
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
                        Spacer()
                        let level = invoice.e1card?.manageLevel ?? .precise
                        // 右肩は状態表示ではなく、決済手段の管理レベルを表示する
                        Text(LocalizedStringKey(level.labelKey))
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(level.badgeColor.opacity(0.18))
                            .foregroundStyle(level.badgeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        .textCase(nil)
                    }
                }
            }
        }
        .scalableNavigationTitle("invoice.statement.title")
        .sheet(item: $editRecord) { record in
            NavigationStack {
                RecordEditView(mode: .edit(record))
            }
        }
    }

    private func toggleInvoicePaid(_ invoice: E2invoice) {
        invoice.isPaid.toggle()
        if let card = invoice.e1card {
            RecordService.recalculateCard(card)
        }
        // 全invoice PAIDになればpaymentもPAID
        let allPaid = payment.e2invoices.allSatisfy { $0.isPaid }
        payment.isPaid = allPaid
        payment.sumNoCheck = payment.e2invoices.reduce(0) { $0 + $1.sumNoCheck }
    }
}

private extension ManagementLevel {
    /// 管理レベルごとの識別色
    var badgeColor: Color {
        switch self {
        case .precise:
            return .blue
        case .approximate:
            return .green
        case .largeOnly:
            return .purple
        }
    }
}

// MARK: - Part Row

private struct PartRow: View {
    let part: E6part
    private var usePointText: String {
        // 利用点は自由入力の記録名を優先し、旧データは店舗名を使う
        if let recordName = part.e3record?.zName, !recordName.isEmpty {
            return recordName
        }
        if let shopName = part.e3record?.e4shop?.zName, !shopName.isEmpty {
            return shopName
        }
        return "—"
    }
    private var dateText: String {
        guard let record = part.e3record else { return "—" }
        return AppDateFormat.singleLineText(record.dateUse)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(usePointText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Spacer()

            Text(part.nAmount.currencyString())
                .font(.body.monospacedDigit())
                .lineLimit(1)
                .layoutPriority(1)
        }
        // 状態表示はセクション右肩ラベル（未払/済み）へ統一する
        .contentShape(Rectangle())
    }
}
