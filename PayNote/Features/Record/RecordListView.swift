import SwiftUI
import SwiftData

struct RecordListView: View {
    @Query(sort: \E1card.nRow)                       private var cards: [E1card]
    @Environment(\.modelContext) private var context

    @State private var filterCard: E1card?
    @State private var filterNoCard = false
    @State private var records: [E3record] = []
    @State private var recordPage = 0
    @State private var hasMoreRecords = true
    @State private var isLoadingRecords = false
    @State private var editTarget: E3record?
    @State private var deleteTarget: E3record?
    @State private var showDeleteAlert = false

    private let pageSize = 100
    private var filtered: [E3record] {
        records
    }
    private var unselectedFilterLabel: String {
        // ロケールに応じて「未選択」ラベルを出し分ける
        Locale.current.identifier.hasPrefix("ja") ? "未選択" : "Unselected"
    }

    var body: some View {
        List {
            ForEach(filtered) { record in
                Button {
                    editTarget = record
                } label: {
                    RecordSummaryRow(record: record)
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

            if hasMoreRecords {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .onAppear {
                    loadMoreRecordsIfNeeded()
                }
            }
        }
        .scalableNavigationTitle("record.list.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                cardFilterPicker
            }
        }
        .sheet(item: $editTarget, onDismiss: {
            // 編集反映後は先頭ページから再読込する
            resetAndLoadRecords()
        }) { record in
            NavigationStack {
                RecordEditView(mode: .edit(record))
            }
        }
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                if let r = deleteTarget {
                    RecordService.delete(r, context: context)
                    // 削除反映後は先頭ページから再読込する
                    resetAndLoadRecords()
                }
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.message")
        }
        .onAppear {
            if records.isEmpty {
                resetAndLoadRecords()
            }
        }
        .onChange(of: filterCard?.id) { _, _ in
            resetAndLoadRecords()
        }
        .onChange(of: filterNoCard) { _, _ in
            resetAndLoadRecords()
        }
    }

    @ViewBuilder
    private var cardFilterPicker: some View {
        Menu {
                Button {
                    filterCard = nil
                    filterNoCard = false
                } label: {
                HStack {
                    Text("label.all")
                    if filterCard == nil && !filterNoCard { Image(systemName: "checkmark") }
                }
            }
                Button {
                    filterCard = nil
                    filterNoCard = true
                } label: {
                HStack {
                    Text(verbatim: unselectedFilterLabel)
                    if filterNoCard { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(cards) { c in
                Button {
                    filterCard = c
                    filterNoCard = false
                } label: {
                    HStack {
                        Text(c.zName)
                        if !filterNoCard && filterCard?.id == c.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "creditcard")
                if filterNoCard {
                    Text(verbatim: unselectedFilterLabel)
                        .font(.subheadline)
                } else if let filterCard {
                    Text(filterCard.zName)
                        .font(.subheadline)
                } else {
                    Text("label.all")
                        .font(.subheadline)
                }
            }
        }
    }

    private func resetAndLoadRecords() {
        recordPage = 0
        hasMoreRecords = true
        records = []
        loadMoreRecordsIfNeeded()
    }

    private func loadMoreRecordsIfNeeded() {
        if isLoadingRecords || !hasMoreRecords {
            return
        }
        isLoadingRecords = true
        defer { isLoadingRecords = false }

        var descriptor: FetchDescriptor<E3record>
        if filterNoCard {
            descriptor = FetchDescriptor<E3record>(
                predicate: #Predicate<E3record> { $0.e1card == nil },
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
        } else if let filterCardID = filterCard?.id {
            descriptor = FetchDescriptor<E3record>(
                predicate: #Predicate<E3record> { $0.e1card?.id == filterCardID },
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<E3record>(
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
        }
        descriptor.fetchOffset = recordPage * pageSize
        descriptor.fetchLimit = pageSize

        let fetched = (try? context.fetch(descriptor)) ?? []
        records.append(contentsOf: fetched)
        recordPage += 1
        hasMoreRecords = pageSize <= fetched.count
    }
}

// MARK: - Shared Row

/// 決済履歴とタグ編集で共用する明細セル
struct RecordSummaryRow: View {
    let record: E3record

    // 分割のどれか1つでも未払があれば未払表示にする
    private var isUnpaid: Bool {
        record.e6parts.contains(where: { ($0.e2invoice?.isPaid ?? false) == false })
    }
    private var statusKey: LocalizedStringKey {
        isUnpaid ? "payment.status.unpaidShort" : "payment.status.paidShort"
    }
    // 金額と同じトーンで文字色を統一する
    private var amountToneColor: Color {
        record.nAmount < 0 ? COLOR_AMOUNT_NEGATIVE : COLOR_AMOUNT_POSITIVE
    }
    // ステータスはカプセルだけ着色する
    private var statusCapsuleColor: Color {
        (isUnpaid ? COLOR_UNPAID : COLOR_PAID).opacity(0.2)
    }
    private var statusTextColor: Color {
        isUnpaid ? COLOR_UNPAID : COLOR_PAID
    }
    private var payMethodText: String {
        record.e1card?.zName ?? "—"
    }
    private var recordLabelText: String {
        // 決済ラベルを優先し、旧データは利用店名へフォールバック
        record.zName.isEmpty ? (record.e4shop?.zName ?? "—") : record.zName
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // 日付は2段表示で固定幅にして視認性をそろえる
            VStack(spacing: 0) {
                Text(AppDateFormat.yearWeekdayText(record.dateUse))
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                Text(AppDateFormat.monthDayText(record.dateUse))
                    .font(.subheadline)
                    .foregroundStyle(amountToneColor)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(recordLabelText)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(amountToneColor)
                    Spacer(minLength: 8)
                    Text(record.nAmount.currencyString())
                        .font(.body.monospacedDigit())
                        .foregroundStyle(amountToneColor)
                }
                HStack(spacing: 6) {
                    Text(statusKey)
                        .font(.caption)
                        .foregroundStyle(statusTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusCapsuleColor)
                        .clipShape(Capsule())
                    Text(payMethodText)
                        .font(.caption)
                        .foregroundStyle(amountToneColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        // セル高さは固定で44ptにする
        .frame(height: 44, alignment: .center)
        .padding(.vertical, 0)
        .contentShape(Rectangle())
    }
}
