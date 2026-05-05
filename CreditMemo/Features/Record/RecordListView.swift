import SwiftUI
import SwiftData

struct RecordListView: View {
    /// フィルターの選択状態を1つの値で扱う
    private enum FilterOption: Hashable {
        case all
        case allByDate
        case incomplete
        case card(String)
    }

    @Query(sort: \E1card.nRow)                       private var cards: [E1card]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner

    @State private var filterCard: E1card?
    @State private var filterIncomplete = false
    @State private var filterDateSort = false
    @State private var records: [E3record] = []
    @State private var recordPage = 0
    @State private var hasMoreRecords = true
    @State private var isLoadingRecords = false
    @State private var editTarget: E3record?
    /// filterIncomplete / "すべて" の全件ソート済みキャッシュ。
    /// ページング時に毎回再ソートしないよう、recordPage == 0 のときだけ再構築する。
    @State private var sortedCache: [E3record] = []

    private let pageSize = 100
    private var allFilterText: String {
        // フィルタの意図を明確化する
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "すべて（保存日時順）"
        }
        return "All (Saved Order)"
    }
    private var allByDateFilterText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "すべて（日付順）"
        }
        return "All (Date Order)"
    }
    private var filtered: [E3record] {
        records
    }
    private var selectedFilterOption: Binding<FilterOption> {
        Binding(
            get: {
                if filterIncomplete { return .incomplete }
                if filterDateSort  { return .allByDate }
                if let filterCard  { return .card(filterCard.id) }
                return .all
            },
            set: { newValue in
                // Pickerの選択値から既存の状態へ戻す
                switch newValue {
                case .all:
                    filterCard = nil
                    filterIncomplete = false
                    filterDateSort = false
                case .allByDate:
                    filterCard = nil
                    filterIncomplete = false
                    filterDateSort = true
                case .incomplete:
                    filterCard = nil
                    filterIncomplete = true
                    filterDateSort = false
                case .card(let id):
                    filterCard = cards.first { $0.id == id }
                    filterIncomplete = false
                    filterDateSort = false
                }
            }
        )
    }

    var body: some View {
        List {
            if userLevel == .beginner {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        (
                            Text("record.list.beginner.guide.leading")
                            + Text(" ")
                            + Text(Image(systemName: "line.3.horizontal.decrease"))
                            + Text(" ")
                            + Text("record.list.beginner.guide.trailing")
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    cardFilterPicker
                }
                .padding(.vertical, 0)
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            ForEach(filtered) { record in
                Button {
                    editTarget = record
                } label: {
                    RecordSummaryRow(record: record)
                }
                .buttonStyle(.plain)
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
        .sheet(item: $editTarget, onDismiss: {
            // 編集反映後は先頭ページから再読込する
            resetAndLoadRecords()
        }) { record in
            NavigationStack {
                RecordEditView(mode: .edit(record))
            }
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
        .onChange(of: filterDateSort) { _, _ in
            resetAndLoadRecords()
        }
    }

    @ViewBuilder
    private var cardFilterPicker: some View {
        Picker(selection: selectedFilterOption) {
            Text(allFilterText)
                .tag(FilterOption.all)
            Text(allByDateFilterText)
                .tag(FilterOption.allByDate)
            Text("record.filter.incomplete")
                .tag(FilterOption.incomplete)
            ForEach(cards) { c in
                Text(c.zName)
                    .tag(FilterOption.card(c.id))
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
    }

    private func resetAndLoadRecords() {
        recordPage = 0
        hasMoreRecords = true
        records = []
        sortedCache = []
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
            // 全件取得後に優先度で並べ替える。再ソートを避けるため recordPage == 0 のときのみ再構築。
            if recordPage == 0 {
                descriptor = FetchDescriptor<E3record>(
                    sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
                )
                let allRecords = (try? context.fetch(descriptor)) ?? []
                sortedCache = allRecords.compactMap { record -> (priority: Int, record: E3record)? in
                    guard let priority = incompletePriority(for: record) else { return nil }
                    return (priority, record)
                }
                .sorted { lhs, rhs in
                    if lhs.priority == rhs.priority {
                        return sortDate(of: rhs.record) < sortDate(of: lhs.record)
                    }
                    return lhs.priority < rhs.priority
                }
                .map(\.record)
            }
            let start = recordPage * pageSize
            let end = min(start + pageSize, sortedCache.count)
            if start < end {
                records.append(contentsOf: sortedCache[start..<end])
            }
            recordPage += 1
            hasMoreRecords = end < sortedCache.count
            return
        } else if filterDateSort {
            // 「すべて（日付順）」は利用日の降順でフェッチする
            descriptor = FetchDescriptor<E3record>(
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
            descriptor.fetchOffset = recordPage * pageSize
            descriptor.fetchLimit = pageSize
            let fetched = (try? context.fetch(descriptor)) ?? []
            records.append(contentsOf: fetched)
            recordPage += 1
            hasMoreRecords = pageSize <= fetched.count
            return
        } else if let filterCardID = filterCard?.id {
            descriptor = FetchDescriptor<E3record>(
                predicate: #Predicate<E3record> { $0.e1card?.id == filterCardID },
                sortBy: [SortDescriptor(\E3record.dateUse, order: .reverse)]
            )
        } else {
            // 「すべて」は利用日ではなく直近入力順で表示する。
            // SwiftData は dateUpdate での直接ソートができないため全件取得後にソート。
            // 再ソートを避けるため recordPage == 0 のときのみ再構築。
            if recordPage == 0 {
                descriptor = FetchDescriptor<E3record>()
                let allRecords = (try? context.fetch(descriptor)) ?? []
                sortedCache = allRecords.sorted { lhs, rhs in
                    sortDate(of: rhs) < sortDate(of: lhs)
                }
            }
            let start = recordPage * pageSize
            let end = min(start + pageSize, sortedCache.count)
            if start < end {
                records.append(contentsOf: sortedCache[start..<end])
            }
            recordPage += 1
            hasMoreRecords = end < sortedCache.count
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
        if record.e5tags.isEmpty {
            return 2
        }
        return nil
    }
}

// MARK: - Shared Row

/// 決済履歴とタグ編集で共用する明細セル
struct RecordSummaryRow: View {
    let record: E3record
    var amountOverride: Decimal? = nil
    var showsStatus: Bool = true

    // 分割のどれか1つでも未払があれば未払表示にする
    private var isUnpaid: Bool {
        // 決済手段未選択などで請求パーツが無い場合は未払として扱う
        if record.e6parts.isEmpty {
            return true
        }
        return record.e6parts.contains(where: { ($0.e2invoice?.isPaid ?? false) == false })
    }
    private var displayAmount: Decimal {
        amountOverride ?? record.nAmount
    }
    // 金額と同じトーンで文字色を統一する
    private var amountToneColor: Color {
        displayAmount < 0 ? COLOR_AMOUNT_NEGATIVE : COLOR_AMOUNT_POSITIVE
    }
    private var statusTextColor: Color {
        isUnpaid ? COLOR_UNPAID : COLOR_PAID
    }
    private var showsRepeatIcon: Bool {
        0 < record.nRepeat
    }
    private var recordLabelText: String {
        // 現行仕様ではラベル未入力時だけダッシュを表示する
        record.zName.isEmpty ? "—" : record.zName
    }
    private var cardNameText: String {
        record.e1card?.zName ?? NSLocalizedString("payment.card.noSelection", comment: "")
    }
    private var categoryNames: [String] {
        record.e5tags.map(\.zName)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // 日付は3段表示にして年・月日・曜日を分ける
            VStack(spacing: 0) {
                Text(AppDateFormat.yearText(record.dateUse))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                Text(AppDateFormat.monthDayText(record.dateUse))
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(AppDateFormat.weekdayText(record.dateUse))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(recordLabelText)
                            .font(.body)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !categoryNames.isEmpty {
                            RecordCategorySingleLineView(names: categoryNames)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recordLabelText)
                            .font(.body)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !categoryNames.isEmpty {
                            RecordCategoryLineView(names: categoryNames)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if showsStatus {
                        // 状態アイコンは控えめに表示する
                        Image(systemName: isUnpaid ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(statusTextColor)
                            .opacity(0.5)
                            .fixedSize(horizontal: true, vertical: false)
                        if showsRepeatIcon {
                            // 未払時だけ、繰り返し予定の印を右へ添える
                            Image(systemName: "repeat")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                                .opacity(0.65)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    Text(cardNameText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(displayAmount.currencyString())
                        .font(.body.monospacedDigit())
                        .foregroundStyle(amountToneColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 2行構成のため最小高さのみ指定して情報を欠けさせない
        .frame(minHeight: 48, alignment: .center)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

/// タグを1行で右寄せし、長いものだけ末尾省略する
private struct RecordCategorySingleLineView: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(names, id: \.self) { name in
                RecordCategoryChip(name: name)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// タグは先頭から順に表示し、収まらない場合は改行する
private struct RecordCategoryLineView: View {
    let names: [String]

    var body: some View {
        TagFlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(names, id: \.self) { name in
                RecordCategoryChip(name: name)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 短いタグは自然幅、長いタグだけ省略できる幅に制限する
private struct RecordCategoryChip: View {
    let name: String

    var body: some View {
        Group {
            if name.count < 9 {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
}

/// タグを左から詰めて折り返す
private struct TagFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat, lineSpacing: CGFloat) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        if maxWidth <= 0 {
            let width = subviews
                .map { $0.sizeThatFits(.unspecified).width }
                .reduce(0, +)
            let height = subviews
                .map { $0.sizeThatFits(.unspecified).height }
                .max() ?? 0
            return CGSize(width: width, height: height)
        }
        let rows = makeRows(maxWidth: maxWidth, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat(0)) { partialResult, row in
            partialResult + row.height
        } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(maxWidth: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            var currentX = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: currentX, y: currentY),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                currentX += size.width + spacing
            }
            currentY += row.height + lineSpacing
        }
    }

    /// 幅に収まる単位で行を組む
    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentIndexes: [Int] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentIndexes.isEmpty ? size.width : currentWidth + spacing + size.width
            if maxWidth < nextWidth && !currentIndexes.isEmpty {
                rows.append(Row(indexes: currentIndexes, width: currentWidth, height: currentHeight))
                currentIndexes = [index]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentIndexes.append(index)
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentIndexes.isEmpty {
            rows.append(Row(indexes: currentIndexes, width: currentWidth, height: currentHeight))
        }
        return rows
    }

    private struct Row {
        let indexes: [Int]
        let width: CGFloat
        let height: CGFloat
    }
}
