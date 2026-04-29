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
                if let c = deleteTarget {
                    try? CardService.delete(c, context: context)
                }
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
                Text(scheduleBadgeText)
                    .font(.caption2)
                    .foregroundStyle(scheduleBadgeForegroundColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scheduleBadgeBackgroundColor)
                    .clipShape(Capsule())
                Text(card.e8bank?.zName ?? "口座未選択")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// 2行目カプセル文言を請求方式ごとに出し分ける
    private var scheduleBadgeText: String {
        if card.billingType == .afterDays {
            let offsetDays = card.offsetDays ?? 0
            if offsetDays == 0 {
                return "利用当日払"
            }
            return "\(offsetDays)日後払"
        }

        // 締日/支払日型
        let closingDayText: String
        if card.nClosingDay == 29 {
            closingDayText = "末日締"
        } else {
            closingDayText = "\(card.nClosingDay)日締"
        }

        let payMonthText: String
        if card.nPayMonth == 0 {
            payMonthText = "当月"
        } else if card.nPayMonth == 1 {
            payMonthText = "翌月"
        } else {
            payMonthText = "翌々月"
        }

        let payDayText: String
        if card.nPayDay == 29 {
            payDayText = "末日払"
        } else {
            payDayText = "\(card.nPayDay)日払"
        }

        return "\(closingDayText)/\(payMonthText)/\(payDayText)"
    }

    /// 請求方式別のカプセル背景色
    private var scheduleBadgeBackgroundColor: Color {
        if card.billingType == .afterDays {
            return Color.cyan.opacity(0.16)
        }
        return Color.indigo.opacity(0.14)
    }

    /// 請求方式別のカプセル文字色
    private var scheduleBadgeForegroundColor: Color {
        if card.billingType == .afterDays {
            return Color.cyan.opacity(0.95)
        }
        return Color.indigo.opacity(0.95)
    }
}
