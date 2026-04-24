import SwiftUI
import SwiftData

struct SplitPayListView: View {
    let record: E3record

    @Environment(\.modelContext) private var context

    private var parts: [E6part] {
        record.e6parts.sorted { $0.nPartNo < $1.nPartNo }
    }

    var body: some View {
        List {
            // レコード情報
            Section {
                LabeledContent("record.field.date") {
                    Text(record.dateUse.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("record.field.amount") {
                    Text(record.nAmount.currencyString())
                        .font(.body.monospacedDigit())
                }
                if let card = record.e1card {
                    LabeledContent("record.field.card") {
                        Text(card.zName)
                    }
                }
                LabeledContent("record.field.payType") {
                    Text(LocalizedStringKey(record.payType.localizedKey))
                }
            }

            // 分割明細
            Section {
                ForEach(parts) { part in
                    PartToggleRow(part: part) {
                        togglePart(part)
                    }
                }
            } header: {
                Text("splitPay.list.title")
            } footer: {
                Text("splitPay.footer")
            }
        }
        .scalableNavigationTitle(verbatim: record.zName.isEmpty
            ? (record.e4shop?.zName ?? "—")
            : record.zName)
    }

    private func togglePart(_ part: E6part) {
        part.isChecked.toggle()

        // 親 invoice の集計を更新
        if let invoice = part.e2invoice {
            if let card = invoice.e1card {
                RecordService.recalculateCard(card)
            }
            if let payment = invoice.e7payment {
                payment.sumNoCheck = payment.e2invoices.reduce(0) { $0 + $1.sumNoCheck }
            }
        }
    }
}

// MARK: - Toggle Row

private struct PartToggleRow: View {
    let part: E6part
    let onToggle: () -> Void

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                Image(systemName: part.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(part.isChecked ? Color(.systemGreen) : Color(.systemGray3))
                    .imageScale(.large)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(part.nPartNo)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("splitPay.part")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let invoice = part.e2invoice {
                        Text(Self.dateFmt.string(from: invoice.date))
                            .font(.subheadline)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(part.nAmount.currencyString())
                        .font(.body.monospacedDigit())
                    if part.nInterest > 0 {
                        Text(String(format: NSLocalizedString("splitPay.interest", comment: "") + " %@",
                                    part.nInterest.currencyString()))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .opacity(part.isChecked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
