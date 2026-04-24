import SwiftUI
import SwiftData

struct InvoiceListView: View {
    let payment: E7payment

    @Environment(\.modelContext) private var context

    private var invoices: [E2invoice] {
        payment.e2invoices.sorted {
            ($0.e1card?.zName ?? "") < ($1.e1card?.zName ?? "")
        }
    }

    var body: some View {
        List {
            // 合計
            Section {
                HStack {
                    Text("label.total")
                    Spacer()
                    Text(payment.sumAmount.currencyString())
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                }
            }

            // カード別請求
            ForEach(invoices) { invoice in
                Section {
                    ForEach(invoice.e6parts.sorted { $0.nPartNo < $1.nPartNo }) { part in
                        NavigationLink {
                            if let record = part.e3record {
                                SplitPayListView(record: record)
                            }
                        } label: {
                            PartRow(part: part)
                        }
                    }

                    // 小計
                    HStack {
                        Spacer()
                        Text(invoice.sumAmount.currencyString())
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(invoice.isPaid ? COLOR_PAID : COLOR_UNPAID)
                    }
                } header: {
                    HStack {
                        Text(invoice.e1card?.zName ?? "—")
                        Spacer()
                        Button {
                            toggleInvoicePaid(invoice)
                        } label: {
                            Text(invoice.isPaid ? "invoice.status.paid" : "invoice.status.unpaid")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(invoice.isPaid
                                    ? COLOR_PAID.opacity(0.2)
                                    : COLOR_UNPAID.opacity(0.2))
                                .foregroundStyle(invoice.isPaid ? COLOR_PAID : COLOR_UNPAID)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .textCase(nil)
                    }
                }
            }
        }
        .scalableNavigationTitle(verbatim: payment.date.formatted(date: .abbreviated, time: .omitted))
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

// MARK: - Part Row

private struct PartRow: View {
    let part: E6part

    var body: some View {
        HStack {
            Image(systemName: part.isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(part.isChecked ? Color(.systemGreen) : Color(.systemGray3))
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 2) {
                Text(part.e3record?.zName ?? (part.e3record?.e4shop?.zName ?? "—"))
                    .font(.body).lineLimit(1)
                if let record = part.e3record {
                    Text(record.dateUse.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(part.nAmount.currencyString())
                    .font(.body.monospacedDigit())
                if part.nInterest > 0 {
                    Text("+ \(part.nInterest.currencyString())")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .opacity(part.isChecked ? 0.5 : 1)
    }
}
