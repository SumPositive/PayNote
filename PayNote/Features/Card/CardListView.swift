import SwiftUI
import SwiftData

struct CardListView: View {
    @Query(sort: \E1card.nRow) private var cards: [E1card]
    @Environment(\.modelContext) private var context

    @State private var showAddSheet    = false
    @State private var deleteTarget: E1card?
    @State private var showDeleteAlert = false

    var body: some View {
        List {
            ForEach(cards) { card in
                NavigationLink {
                    CardEditView(card: card)
                } label: {
                    CardRow(card: card)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget    = card
                        showDeleteAlert = true
                    } label: {
                        Label("button.delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: move)
        }
        .scalableNavigationTitle("card.list.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack { CardEditView(card: nil) }
        }
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                if let c = deleteTarget { context.delete(c) }
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.message")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = cards
        list.move(fromOffsets: source, toOffset: destination)
        for (i, c) in list.enumerated() { c.nRow = Int32(i) }
    }
}

// MARK: - Row

private struct CardRow: View {
    let card: E1card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card.zName).font(.body)
                Spacer()
                if card.sumUnpaid != .zero {
                    Text(card.sumUnpaid.currencyString())
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(COLOR_UNPAID)
                }
            }
            HStack(spacing: 8) {
                if let bank = card.e8bank {
                    Text(bank.zName).font(.caption).foregroundStyle(.secondary)
                }
                if !card.manageLevel.isDefault {
                    Text(LocalizedStringKey(card.manageLevel.labelKey))
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(.systemFill))
                        .clipShape(Capsule())
                }
                if card.isDebit {
                    Text("card.closingDay.debitLegacy")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(.systemFill))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
