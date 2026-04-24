import SwiftUI
import SwiftData

struct RecordListView: View {
    @Query(sort: \E3record.dateUse, order: .reverse) private var records: [E3record]
    @Query(sort: \E1card.nRow)                       private var cards: [E1card]
    @Environment(\.modelContext) private var context

    @State private var filterCard: E1card?
    @State private var editTarget: E3record?
    @State private var deleteTarget: E3record?
    @State private var showDeleteAlert = false

    private var filtered: [E3record] {
        guard let filterCard else { return records }
        return records.filter { $0.e1card?.id == filterCard.id }
    }

    var body: some View {
        List {
            ForEach(filtered) { record in
                Button {
                    editTarget = record
                } label: {
                    RecordRow(record: record)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget   = record
                        showDeleteAlert = true
                    } label: {
                        Label("button.delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        editTarget = record
                    } label: {
                        Label("button.edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .scalableNavigationTitle("record.list.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                cardFilterPicker
            }
        }
        .sheet(item: $editTarget) { record in
            NavigationStack {
                RecordEditView(mode: .edit(record))
            }
        }
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                if let r = deleteTarget {
                    RecordService.delete(r, context: context)
                }
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.message")
        }
    }

    @ViewBuilder
    private var cardFilterPicker: some View {
        Menu {
            Button {
                filterCard = nil
            } label: {
                HStack {
                    Text("label.all")
                    if filterCard == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(cards) { c in
                Button {
                    filterCard = c
                } label: {
                    HStack {
                        Text(c.zName)
                        if filterCard?.id == c.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "creditcard")
                Text(filterCard?.zName ?? "label.all")
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Row

private struct RecordRow: View {
    let record: E3record

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.zNote.isEmpty ? (record.e4shop?.zName ?? "—") : record.zNote)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.dateFmt.string(from: record.dateUse))
                        .font(.caption).foregroundStyle(.secondary)
                    if let card = record.e1card {
                        Text(card.zName)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(.systemFill))
                            .clipShape(Capsule())
                    }
                    if record.payType == .twoPayments {
                        Text("payType.twoPayments")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(.systemBlue).opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Text(record.nAmount.currencyString())
                .font(.body.monospacedDigit())
                .foregroundStyle(record.nAmount < 0 ? COLOR_AMOUNT_NEGATIVE : COLOR_AMOUNT_POSITIVE)
        }
        .padding(.vertical, 2)
    }
}
