import SwiftUI
import SwiftData

struct RecordListView: View {
    @Query(sort: \E1card.nRow)                       private var cards: [E1card]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner

    @State private var filterCard: E1card?
    @State private var filterIncomplete = false
    @State private var records: [E3record] = []
    @State private var recordPage = 0
    @State private var hasMoreRecords = true
    @State private var isLoadingRecords = false
    @State private var editTarget: E3record?
    @State private var deleteTarget: E3record?
    @State private var showDeleteAlert = false

    private let pageSize = 100
    private var allFilterText: String {
        // フィルタの意図を明確化する
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "すべて（保存日時順）"
        }
        return "All (Saved Order)"
    }
    private var filtered: [E3record] {
        records
    }

    var body: some View {
        List {
            if userLevel == .beginner {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("record.list.beginner.title")
                            .font(.subheadline.weight(.semibold))
                        Text("record.list.beginner.guide")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
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
                    try? RecordService.delete(r, context: context)
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
        .onChange(of: filterIncomplete) { _, _ in
            resetAndLoadRecords()
        }
    }

    @ViewBuilder
    private var cardFilterPicker: some View {
        Menu {
                Button {
                    filterCard = nil
                    filterIncomplete = false
                } label: {
                HStack {
                    Text(allFilterText)
                    if filterCard == nil && !filterIncomplete { Image(systemName: "checkmark") }
                }
            }
                Button {
                    filterCard = nil
                    filterIncomplete = true
                } label: {
                HStack {
                    Text("record.filter.incomplete")
                    if filterIncomplete { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(cards) { c in
                Button {
                    filterCard = c
                    filterIncomplete = false
                } label: {
                    HStack {
                        Text(c.zName)
                        if !filterIncomplete && filterCard?.id == c.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "creditcard")
                if filterIncomplete {
                    Text("record.filter.incomplete")
                        .font(.subheadline)
                } else if let filterCard {
                    Text(filterCard.zName)
                        .font(.subheadline)
                } else {
                    Text(allFilterText)
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
        if filterIncomplete {
            // 情報不足フィルタは「決済手段→決済ラベル→タグ」の優先順が必要なため、
            // ここだけ全件取得後に優先度で並べ替えてからページングする
            descriptor = FetchDescriptor<E3record>(
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
            let allRecords = (try? context.fetch(descriptor)) ?? []
            let ranked = allRecords.compactMap { record -> (priority: Int, record: E3record)? in
                guard let priority = incompletePriority(for: record) else { return nil }
                return (priority, record)
            }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return sortDate(of: rhs.record) < sortDate(of: lhs.record)
                }
                return lhs.priority < rhs.priority
            }

            let start = recordPage * pageSize
            let end = min(start + pageSize, ranked.count)
            if start < end {
                records.append(contentsOf: ranked[start..<end].map(\.record))
            }
            recordPage += 1
            hasMoreRecords = end < ranked.count
            return
        } else if let filterCardID = filterCard?.id {
            descriptor = FetchDescriptor<E3record>(
                predicate: #Predicate<E3record> { $0.e1card?.id == filterCardID },
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
        } else {
            // 「すべて」は利用日ではなく直近入力順で表示する
            descriptor = FetchDescriptor<E3record>()
            let allRecords = (try? context.fetch(descriptor)) ?? []
            let sorted = allRecords.sorted { lhs, rhs in
                sortDate(of: rhs) < sortDate(of: lhs)
            }
            let start = recordPage * pageSize
            let end = min(start + pageSize, sorted.count)
            if start < end {
                records.append(contentsOf: sorted[start..<end])
            }
            recordPage += 1
            hasMoreRecords = end < sorted.count
            return
        }
        descriptor.fetchOffset = recordPage * pageSize
        descriptor.fetchLimit = pageSize

        let fetched = (try? context.fetch(descriptor)) ?? []
        records.append(contentsOf: fetched)
        recordPage += 1
        hasMoreRecords = pageSize <= fetched.count
    }

    /// 入力順ソート用の代表日時（未設定時は利用日へフォールバック）
    private func sortDate(of record: E3record) -> Date {
        record.dateUpdate ?? record.dateUse
    }

    /// 情報不足の優先順位（小さいほど優先）
    /// 1) 決済手段未設定 2) 決済ラベル未設定 3) タグ未設定
    private func incompletePriority(for record: E3record) -> Int? {
        if record.e1card == nil {
            return 0
        }
        let label = record.zName.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            return 1
        }
        if record.e5categories.isEmpty && record.e5category == nil {
            return 2
        }
        return nil
    }
}

// MARK: - Shared Row

/// 決済履歴とタグ編集で共用する明細セル
struct RecordSummaryRow: View {
    let record: E3record

    // 分割のどれか1つでも未払があれば未払表示にする
    private var isUnpaid: Bool {
        // 決済手段未選択などで請求パーツが無い場合は未払として扱う
        if record.e6parts.isEmpty {
            return true
        }
        return record.e6parts.contains(where: { ($0.e2invoice?.isPaid ?? false) == false })
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
    private var hasMissingSelection: Bool {
        // 決済手段未選択、または引き落とし口座未選択のときに未アイコンを出す
        if record.e1card == nil {
            return true
        }
        return record.e1card?.e8bank == nil
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
                }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(spacing: 6) {
                        Text(statusKey)
                            .font(.caption)
                            .foregroundStyle(statusTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusCapsuleColor)
                            .clipShape(Capsule())
                        if hasMissingSelection {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(COLOR_UNPAID)
                        }
                        }
                        .layoutPriority(0)
                        Spacer(minLength: 8)
                        Text(record.nAmount.currencyString())
                            .font(.body.monospacedDigit())
                            .foregroundStyle(amountToneColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                    }
                }
            }
        // 2行構成のため最小高さのみ指定して情報を欠けさせない
        .frame(minHeight: 52, alignment: .center)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
