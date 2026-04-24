import SwiftUI
import SwiftData

struct PaymentListView: View {
    @Query(sort: \E7payment.date, order: .reverse) private var payments: [E7payment]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            let unpaid = payments.filter { !$0.isPaid }
            let paid   = payments.filter {  $0.isPaid }

            if !unpaid.isEmpty {
                Section {
                    ForEach(unpaid) { payment in
                        NavigationLink {
                            InvoiceListView(payment: payment)
                        } label: {
                            PaymentRow(payment: payment) {
                                togglePaid(payment)
                            }
                        }
                    }
                } header: {
                    Text("invoice.status.unpaid")
                }
            }

            if !paid.isEmpty {
                Section {
                    ForEach(paid) { payment in
                        NavigationLink {
                            InvoiceListView(payment: payment)
                        } label: {
                            PaymentRow(payment: payment) {
                                togglePaid(payment)
                            }
                        }
                    }
                } header: {
                    Text("invoice.status.paid")
                }
            }

            if payments.isEmpty {
                ContentUnavailableView("label.empty",
                    systemImage: "calendar.badge.clock")
            }
        }
        .scalableNavigationTitle("payment.list.title")
    }

    private func togglePaid(_ payment: E7payment) {
        payment.isPaid.toggle()
        // すべての子 invoice に伝播
        for inv in payment.e2invoices {
            inv.isPaid = payment.isPaid
            if payment.isPaid, let card = inv.e1card {
                // repeat が必要なレコードを生成
                for part in inv.e6parts {
                    if let record = part.e3record, record.nRepeat > 0 {
                        let existsNext = record.e1card?.e3records.contains(where: {
                            Calendar.current.isDate($0.dateUse,
                                equalTo: Calendar.current.date(byAdding: .month,
                                    value: Int(record.nRepeat), to: record.dateUse) ?? Date(),
                                toGranularity: .month)
                        }) ?? false
                        if !existsNext {
                            RecordService.makeRepeatRecord(from: record, context: context)
                        }
                    }
                }
                RecordService.recalculateCard(card)
            }
        }
    }
}

// MARK: - Row

private struct PaymentRow: View {
    let payment: E7payment
    let onToggle: () -> Void

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // PAID/UNPAID バッジ
            Button(action: onToggle) {
                Text(payment.isPaid ? "invoice.status.paid" : "invoice.status.unpaid")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(payment.isPaid ? COLOR_PAID.opacity(0.2) : COLOR_UNPAID.opacity(0.2))
                    .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dateFmt.string(from: payment.date))
                    .font(.body)
                Text("\(payment.e2invoices.count) " + NSLocalizedString("label.cards", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(payment.sumAmount.currencyString())
                    .font(.body.monospacedDigit())
                    .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                if payment.sumNoCheck > 0 {
                    Text("✕ \(payment.sumNoCheck)")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
