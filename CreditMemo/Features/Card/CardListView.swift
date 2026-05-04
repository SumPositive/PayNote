import SwiftUI
import SwiftData

struct CardListView: View {
    @Query(sort: \E1card.nRow) private var cards: [E1card]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner

    @State private var showAddSheet    = false
    @State private var deleteTarget: E1card?
    @State private var showDeleteAlert = false

    var body: some View {
        List {
            if userLevel == .beginner {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("card.beginner.line1")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("card.beginner.line2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("card.beginner.line3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
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
    private var isEnglishLocale: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en") == "en"
    }

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scheduleBadgeBackgroundColor)
                    .clipShape(Capsule())
                    // 請求方式カプセルは改行させず、内容を優先して保持する
                    .fixedSize(horizontal: true, vertical: false)
                Text(card.e8bank?.zName ?? NSLocalizedString("payment.bank.noSelection", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // 口座名だけを可変幅にして、末尾省略の対象にする
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// 2行目カプセル文言を請求方式ごとに出し分ける
    private var scheduleBadgeText: String {
        if card.nClosingDay == 0 {
            let daysLater = Int(card.nPayDay)
            if daysLater == 0 {
                return NSLocalizedString("card.schedule.sameDay", comment: "")
            }
            return String(format: NSLocalizedString("card.schedule.afterDays", comment: ""), daysLater)
        }

        // 締日/支払日型
        let closingDayText: String
        if card.nClosingDay == 29 {
            closingDayText = NSLocalizedString("card.schedule.closing.end", comment: "")
        } else {
            closingDayText = String(format: NSLocalizedString("card.schedule.closing.day", comment: ""), card.nClosingDay)
        }

        let payMonthText: String
        if card.nPayMonth == 0 {
            payMonthText = NSLocalizedString("card.payMonth.current", comment: "")
        } else if card.nPayMonth == 1 {
            payMonthText = NSLocalizedString("card.payMonth.next", comment: "")
        } else {
            payMonthText = NSLocalizedString("card.payMonth.twoMonths", comment: "")
        }

        let payDayText: String
        if card.nPayDay == 29 {
            payDayText = NSLocalizedString("card.schedule.pay.end", comment: "")
        } else {
            payDayText = String(format: NSLocalizedString("card.schedule.pay.day", comment: ""), card.nPayDay)
        }

        let separator = isEnglishLocale ? " / " : "/"
        return "\(closingDayText)\(separator)\(payMonthText)\(separator)\(payDayText)"
    }

    /// 請求方式別のカプセル背景色
    private var scheduleBadgeBackgroundColor: Color {
        if card.nClosingDay == 0 {
            return Color.cyan.opacity(0.16)
        }
        return Color.indigo.opacity(0.14)
    }

    /// 請求方式別のカプセル文字色
    private var scheduleBadgeForegroundColor: Color {
        if card.nClosingDay == 0 {
            return Color.cyan.opacity(0.95)
        }
        return Color.indigo.opacity(0.95)
    }
}
