import SwiftUI
import SwiftData
import UIKit

struct PaymentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \E8bank.nRow) private var banks: [E8bank]
    @Query(sort: \E1card.nRow) private var cards: [E1card]
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner
    @AppStorage(AppStorageKey.paymentWindowDays) private var paymentWindowDays = 15
    @State private var upcomingUnpaidPayments: [E7payment] = []
    @State private var overdueUnpaidPayments: [E7payment] = []
    @State private var overdueUnpaidCount = 0
    @State private var paidPayments: [E7payment] = []
    @State private var allPaidCount = 0
    @State private var isLoadingMorePaid = false
    @State private var unpaidFilter: PaymentUnpaidFilter = .upcoming
    @State private var groupMode: PaymentGroupMode = .date
    @State private var filterMode: PaymentFilterMode = .all
    @State private var selectedBank: E8bank?
    @State private var selectedCard: E1card?
    @State private var showBankPicker = false
    @State private var showCardPicker = false
    @State private var togglingPaymentIDs: Set<String> = []
    /// false のとき自動スクロールをスキップする
    @State private var autoScrollEnabled = true
    private let paymentMoveAnimation = Animation.easeInOut(duration: 0.55)
    private let pageSize = 100
    private let overduePageSize = 100
    private let paymentBoundaryAnchorID = "payment-boundary-anchor"
    private let paidFirstRowAnchorID = "payment-paid-first-row-anchor"

    private var paymentStatusStartDate: Date {
        // 引き落とし状況は、古い決済で画面が重くならないよう直近1年だけを対象にする
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .year, value: -1, to: today) ?? today
    }

    private var hasMorePaid: Bool {
        paidPayments.count < allPaidCount
    }

    private var hasOverdueUnpaid: Bool {
        0 < overdueUnpaidCount
    }

    private var selectedUnpaidPayments: [E7payment] {
        unpaidFilter == .upcoming ? upcomingUnpaidPayments : overdueUnpaidPayments
    }

    private var selectedUnpaidItems: [PaymentDisplayItem] {
        buildDisplayItems(from: selectedUnpaidPayments, isPaid: false)
    }

    private var paidItems: [PaymentDisplayItem] {
        buildDisplayItems(from: paidPayments, isPaid: true)
    }

    private var hasAnyPayments: Bool {
        !upcomingUnpaidPayments.isEmpty || 0 < overdueUnpaidCount || !paidPayments.isEmpty
    }

    private var scrollPositionKey: String {
        // カウントを含めることで初回データ読み込み後に確実に発火させる。
        // 戻り時の不要スクロールは suppressNextScroll フラグで抑制する。
        "\(unpaidFilter.rawValue)-\(groupMode.rawValue)-\(filterMode.rawValue)-\(selectedBank?.id ?? "")-\(selectedCard?.id ?? "")-\(selectedUnpaidItems.count)-\(paidItems.count)"
    }

    var body: some View {
        Group {
            if !hasAnyPayments {
                ContentUnavailableView("label.empty", systemImage: "calendar.badge.clock")
            } else {
                VStack(spacing: 0) {
                    PaymentDisplayControlBar(
                        groupMode: $groupMode,
                        filterMode: $filterMode,
                        selectedBankName: selectedBank?.zName,
                        selectedCardName: selectedCard?.zName,
                        onSelectBank: { showBankPicker = true },
                        onSelectCard: { showCardPicker = true },
                        onClearFilter: {
                            selectedBank = nil
                            selectedCard = nil
                            filterMode = .all
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    if hasOverdueUnpaid {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(unpaidFilter == .upcoming
                                ? "payment.overdue.warning.upcoming"
                                : "payment.overdue.warning.past"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(COLOR_UNPAID)
                            // ja/en とも警告文は1行に収めるため、必要に応じて文字を縮小する。
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            Picker("payment.overdue.filter", selection: $unpaidFilter) {
                                Text("payment.overdue.upcoming").tag(PaymentUnpaidFilter.upcoming)
                                Text("payment.overdue.past").tag(PaymentUnpaidFilter.overdue)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if userLevel == .beginner {
                                    VStack(alignment: .center, spacing: 4) {
                                        Text("payment.beginner.title")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                        // 文とアイコン付き操作文を分け、改行位置を自然にする
                                        VStack(alignment: .center, spacing: 1) {
                                            Text("payment.beginner.line1")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                                .multilineTextAlignment(.center)
                                                .fixedSize(horizontal: false, vertical: true)
                                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                                PaymentStatusPill(isPaid: false)
                                                    .scaleEffect(0.52)
                                                Text("payment.beginner.line2")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .multilineTextAlignment(.center)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        VStack(alignment: .center, spacing: 1) {
                                            Text("payment.beginner.line3")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                                .multilineTextAlignment(.center)
                                                .fixedSize(horizontal: false, vertical: true)
                                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                                PaymentStatusPill(isPaid: true)
                                                    .scaleEffect(0.52)
                                                Text("payment.beginner.line4")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .multilineTextAlignment(.center)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                PaymentCombinedCard(
                                    unpaidItems: selectedUnpaidItems,
                                    paidItems: paidItems,
                                    unpaidFilter: unpaidFilter,
                                    onToggle: togglePaid,
                                    togglingPaymentIDs: togglingPaymentIDs,
                                    hasMorePaid: hasMorePaid,
                                    onLoadMorePaid: loadMorePaidIfNeeded,
                                    boundaryAnchorID: paymentBoundaryAnchorID,
                                    paidFirstRowAnchorID: paidFirstRowAnchorID,
                                    windowDays: paymentWindowDays,
                                    onNavigateToDetail: { autoScrollEnabled = false }
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .id(unpaidFilter)
                        .task(id: scrollPositionKey) {
                            await scrollToInitialPosition(proxy: proxy)
                        }
                    }
                }
            }
        }
        .scalableNavigationTitle("payment.list.title")
        .onAppear {
            loadInitialPayments()
            // 詳細から戻ったとき（autoScrollEnabled が OFF）は復元タスクを立てる。
            // タスクが発火すれば scrollToInitialPosition 内で ON へ戻るため、タイムアウトは保険
            if !autoScrollEnabled {
                Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    autoScrollEnabled = true
                }
            }
        }
        .sheet(isPresented: $showBankPicker) {
            PaymentFilterPickerSheet(
                title: "payment.filter.bank",
                items: banks,
                selected: $selectedBank,
                label: { $0.zName },
                noSelectionTitle: "label.all"
            )
            .onDisappear {
                filterMode = selectedBank == nil ? .all : .bank
            }
        }
        .sheet(isPresented: $showCardPicker) {
            PaymentFilterPickerSheet(
                title: "payment.filter.card",
                items: cards,
                selected: $selectedCard,
                label: { $0.zName },
                noSelectionTitle: "label.all"
            )
            .onDisappear {
                filterMode = selectedCard == nil ? .all : .card
            }
        }
    }

    /// 未払は「今後」と「過去」で分け、済みはページ単位で読む
    private func loadInitialPayments() {
        upcomingUnpaidPayments = fetchUpcomingUnpaidPayments()
        overdueUnpaidCount = fetchOverdueUnpaidCount()
        overdueUnpaidPayments = fetchOverdueUnpaidPayments(limit: overduePageSize)
        if overdueUnpaidCount <= 0 {
            unpaidFilter = .upcoming
        }
        allPaidCount = fetchPaidCount()
        paidPayments = fetchPaidPayments(offset: 0, limit: pageSize)
    }

    private func scrollToInitialPosition(proxy: ScrollViewProxy) async {
        // 詳細から戻ったときなど、スクロール OFF のときはスキップして次回のために ON へ戻す
        guard autoScrollEnabled else {
            autoScrollEnabled = true
            return
        }
        // レイアウト確定後に境界を中央へ寄せる
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(paymentBoundaryAnchorID, anchor: .center)
            }
        }
    }

    private func togglePaid(_ item: PaymentDisplayItem) {
        // 連打で同じ支払を二重更新しないよう、短時間ロックする
        if togglingPaymentIDs.contains(item.id) {
            return
        }
        let previousIsPaid = item.isPaid
        let nextIsPaid = !previousIsPaid
        // 決済手段未選択を含む支払は、未払→済みへの更新を禁止する
        if !previousIsPaid && item.includesUnselectedCard {
            return
        }
        // 未払→済みは重め、済み→未払は軽めの触覚フィードバック
        let style: UIImpactFeedbackGenerator.FeedbackStyle = nextIsPaid ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        togglingPaymentIDs.insert(item.id)
        applyPaidState(item, isPaid: nextIsPaid)
        Task { @MainActor in
            // 画面更新が落ち着くまで短くロックを残す
            try? await Task.sleep(nanoseconds: 400_000_000)
            togglingPaymentIDs.remove(item.id)
        }
    }

    private func applyPaidState(_ item: PaymentDisplayItem, isPaid: Bool) {
        withAnimation(paymentMoveAnimation) {
            // 未払/済みの変更はサービス層でまとめて保存する
            try? RecordService.setInvoicesPaid(
                item.invoices,
                isPaid: isPaid,
                context: context
            )
            // 更新後は一覧を読み直して境界付近を正しく保つ
            reloadPaymentsKeepingPaidPage()
        }
    }

    /// 現在の済み表示件数を保ったまま再読込する
    private func reloadPaymentsKeepingPaidPage() {
        let currentPaidCount = paidPayments.count
        upcomingUnpaidPayments = fetchUpcomingUnpaidPayments()
        overdueUnpaidCount = fetchOverdueUnpaidCount()
        overdueUnpaidPayments = fetchOverdueUnpaidPayments(limit: overduePageSize)
        if overdueUnpaidCount <= 0 {
            unpaidFilter = .upcoming
        }
        allPaidCount = fetchPaidCount()
        let nextLimit = max(pageSize, currentPaidCount)
        paidPayments = fetchPaidPayments(offset: 0, limit: nextLimit)
    }

    private func loadMorePaidIfNeeded() {
        if !hasMorePaid {
            return
        }
        if isLoadingMorePaid {
            return
        }
        isLoadingMorePaid = true
        let nextPage = fetchPaidPayments(offset: paidPayments.count, limit: pageSize)
        paidPayments.append(contentsOf: nextPage)
        isLoadingMorePaid = false
    }

    /// 当日以降の未払は通常表示の対象として全件読む
    private func fetchUpcomingUnpaidPayments() -> [E7payment] {
        let today = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<E7payment> { today <= $0.date }
        let descriptor = FetchDescriptor<E7payment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\E7payment.date, order: .reverse)]
        )
        // 表示状態は invoice 側の paid/unpaid を正とする
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isPaid }
    }

    /// 前日以前の未払件数だけを先に取る
    private func fetchOverdueUnpaidCount() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let startDate = paymentStatusStartDate
        let predicate = #Predicate<E7payment> { startDate <= $0.date && $0.date < today }
        let descriptor = FetchDescriptor<E7payment>(predicate: predicate)
        // 口座未選択の済みも混ざりうるため、件数も実状態で数える
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isPaid }.count
    }

    /// 前日以前の未払は最大件数だけ表示する
    private func fetchOverdueUnpaidPayments(limit: Int) -> [E7payment] {
        let today = Calendar.current.startOfDay(for: Date())
        let startDate = paymentStatusStartDate
        let predicate = #Predicate<E7payment> { startDate <= $0.date && $0.date < today }
        let descriptor = FetchDescriptor<E7payment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\E7payment.date, order: .reverse)]
        )
        let fetched = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isPaid }
        // 直近の過去未払から limit 件だけ取り、表示は古い順へ戻す
        return Array(fetched.prefix(limit).reversed())
    }

    /// 済み件数だけ先に取り、ページングの終端判定に使う
    private func fetchPaidCount() -> Int {
        let startDate = paymentStatusStartDate
        let predicate = #Predicate<E7payment> { startDate <= $0.date }
        let descriptor = FetchDescriptor<E7payment>(predicate: predicate)
        // 口座未選択でも済みになりうるため、件数は実状態で数える
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isPaid).count
    }

    /// 済みは必要件数だけ読む
    private func fetchPaidPayments(offset: Int, limit: Int) -> [E7payment] {
        let startDate = paymentStatusStartDate
        let predicate = #Predicate<E7payment> { startDate <= $0.date }
        let descriptor = FetchDescriptor<E7payment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\E7payment.date, order: .reverse)]
        )
        let paid = ((try? context.fetch(descriptor)) ?? []).filter(\.isPaid)
        if paid.count <= offset {
            return []
        }
        let end = min(paid.count, offset + limit)
        return Array(paid[offset..<end])
    }

    private func buildDisplayItems(from payments: [E7payment], isPaid: Bool) -> [PaymentDisplayItem] {
        // E7payment は「日付+口座」単位なので、画面の集計軸に合わせて表示用モデルへ変換する
        switch groupMode {
        case .bank:
            return payments.compactMap { payment in
                let invoices = filteredInvoices(in: payment.e2invoices)
                if invoices.isEmpty {
                    return nil
                }
                return PaymentDisplayItem(
                    id: "bank-\(payment.id)-\(filterMode.rawValue)-\(selectedCard?.id ?? "")",
                    date: payment.date,
                    title: bankTitle(for: payment),
                    amount: invoices.reduce(Decimal.zero) { $0 + $1.sumAmount },
                    isPaid: isPaid,
                    invoices: invoices,
                    detailPayment: payment
                )
            }
            .sorted { $1.date < $0.date }
        case .date:
            let invoices = payments.flatMap { filteredInvoices(in: $0.e2invoices) }
            return groupedItems(
                invoices: invoices,
                isPaid: isPaid,
                key: { invoice in "date-\(dayKey(invoice.date))" },
                title: { _ in dateGroupTitleText }
            )
        case .card:
            let invoices = payments.flatMap { filteredInvoices(in: $0.e2invoices) }
            return groupedItems(
                invoices: invoices,
                isPaid: isPaid,
                key: { invoice in "card-\(dayKey(invoice.date))-\(invoice.e1card?.id ?? "__no_card__")" },
                title: { invoice in invoice.e1card?.zName ?? NSLocalizedString("payment.card.noSelection", comment: "") }
            )
        }
    }

    private func filteredInvoices(in invoices: [E2invoice]) -> [E2invoice] {
        // 絞り込みは集計軸とは独立して適用する
        invoices.filter { invoice in
            switch filterMode {
            case .all:
                return true
            case .bank:
                return invoice.e7payment?.e8bank?.id == selectedBank?.id
            case .card:
                return invoice.e1card?.id == selectedCard?.id
            }
        }
    }

    private var dateGroupTitleText: String {
        // 日付集計でも、絞り込み中は対象名を行タイトルに出す
        switch filterMode {
        case .all:
            return NSLocalizedString("payment.group.date.all", comment: "")
        case .bank:
            return selectedBank?.zName ?? NSLocalizedString("payment.filter.bank", comment: "")
        case .card:
            return selectedCard?.zName ?? NSLocalizedString("payment.filter.card", comment: "")
        }
    }

    private func groupedItems(
        invoices: [E2invoice],
        isPaid: Bool,
        key: (E2invoice) -> String,
        title: (E2invoice) -> String
    ) -> [PaymentDisplayItem] {
        var buckets: [String: [E2invoice]] = [:]
        var titles: [String: String] = [:]
        for invoice in invoices {
            let bucketKey = key(invoice)
            buckets[bucketKey, default: []].append(invoice)
            titles[bucketKey] = title(invoice)
        }
        return buckets.map { bucketKey, bucketInvoices in
            let date = bucketInvoices.map(\.date).min() ?? Date()
            return PaymentDisplayItem(
                id: "\(isPaid ? "paid" : "unpaid")-\(bucketKey)",
                date: date,
                title: titles[bucketKey] ?? "",
                amount: bucketInvoices.reduce(Decimal.zero) { $0 + $1.sumAmount },
                isPaid: isPaid,
                invoices: bucketInvoices,
                detailPayment: uniquePayment(in: bucketInvoices)
            )
        }
        .sorted { $1.date < $0.date }
    }

    private func uniquePayment(in invoices: [E2invoice]) -> E7payment? {
        // 複数支払を束ねた行では、誤った明細へ遷移しないよう詳細遷移を出さない
        let payments = invoices.compactMap(\.e7payment)
        guard let first = payments.first else { return nil }
        if payments.allSatisfy({ $0.id == first.id }) {
            return first
        }
        return nil
    }

    private func bankTitle(for payment: E7payment) -> String {
        if !payment.hasAnySelectedCard && payment.includesUnselectedCard {
            return NSLocalizedString("payment.card.noSelection", comment: "")
        }
        if let bankName = payment.e8bank?.zName, !bankName.isEmpty {
            return bankName
        }
        return NSLocalizedString("payment.bank.noSelection", comment: "")
    }

    private func dayKey(_ date: Date) -> Int {
        Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
    }
}

private enum PaymentUnpaidFilter: String {
    case upcoming
    case overdue
}

private enum PaymentGroupMode: String, CaseIterable {
    case date
    case bank
    case card

    var localizedKey: LocalizedStringKey {
        switch self {
        case .date: "payment.group.date"
        case .bank: "payment.group.bank"
        case .card: "payment.group.card"
        }
    }
}

private enum PaymentFilterMode: String, CaseIterable {
    case all
    case bank
    case card

    var localizedKey: LocalizedStringKey {
        switch self {
        case .all: "label.all"
        case .bank: "payment.filter.bank"
        case .card: "payment.filter.card"
        }
    }
}

struct PaymentDisplayItem: Identifiable {
    let id: String
    let date: Date
    let title: String
    let amount: Decimal
    let isPaid: Bool
    let invoices: [E2invoice]
    let detailPayment: E7payment?

    var includesUnselectedCard: Bool {
        invoices.contains { $0.e1card == nil }
    }
}

private struct PaymentDisplayControlBar: View {
    @Binding var groupMode: PaymentGroupMode
    @Binding var filterMode: PaymentFilterMode
    let selectedBankName: String?
    let selectedCardName: String?
    let onSelectBank: () -> Void
    let onSelectCard: () -> Void
    let onClearFilter: () -> Void

    private var filterTitle: String {
        // 絞り込み状態を1つのチップに集約して、長い名称でも崩れにくくする
        switch filterMode {
        case .all:
            return NSLocalizedString("label.all", comment: "")
        case .bank:
            let name = selectedBankName ?? NSLocalizedString("payment.filter.bank", comment: "")
            return String(format: NSLocalizedString("payment.filter.bankPrefix", comment: ""), name)
        case .card:
            let name = selectedCardName ?? NSLocalizedString("payment.filter.card", comment: "")
            return String(format: NSLocalizedString("payment.filter.cardPrefix", comment: ""), name)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaymentGroupSegmentedControl(selection: $groupMode)
            PaymentFilterStatusBar(
                title: filterTitle,
                isFiltered: filterMode != .all,
                onSelectAll: onClearFilter,
                onSelectBank: onSelectBank,
                onSelectCard: onSelectCard,
                onClear: onClearFilter
            )
        }
    }
}

private struct PaymentGroupSegmentedControl: View {
    @Binding var selection: PaymentGroupMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PaymentGroupMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.localizedKey)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == mode ? Color(uiColor: .systemBackground) : Color.clear)
                                .shadow(color: selection == mode ? Color.black.opacity(0.10) : .clear, radius: 1, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}

private struct PaymentFilterStatusBar: View {
    let title: String
    let isFiltered: Bool
    let onSelectAll: () -> Void
    let onSelectBank: () -> Void
    let onSelectCard: () -> Void
    let onClear: () -> Void
    @State private var showFilterMenu = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showFilterMenu = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.medium)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFiltered ? Color.white : Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule()
                        .fill(isFiltered ? Color.accentColor : Color.accentColor.opacity(0.10))
                )
            }
            .buttonStyle(.plain)

            if isFiltered {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("label.all"))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        .confirmationDialog("payment.filter.title", isPresented: $showFilterMenu, titleVisibility: .visible) {
            Button("label.all") {
                onSelectAll()
            }
            Button("payment.filter.bank") {
                onSelectBank()
            }
            Button("payment.filter.card") {
                onSelectCard()
            }
            Button("button.cancel", role: .cancel) {}
        }
    }
}

private struct PaymentFilterPickerSheet<T: Identifiable>: View where T.ID: Equatable {
    let title: LocalizedStringKey
    let items: [T]
    @Binding var selected: T?
    let label: (T) -> String
    let noSelectionTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selected = nil
                    dismiss()
                } label: {
                    pickerRow(title: NSLocalizedString(noSelectionTitle, comment: ""), isSelected: selected == nil)
                }
                ForEach(items) { item in
                    Button {
                        selected = item
                        dismiss()
                    } label: {
                        pickerRow(title: label(item), isSelected: selected?.id == item.id)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pickerRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Row

private struct PaymentRow: View {
    let item: PaymentDisplayItem
    let isToggling: Bool
    let onToggle: () -> Void
    private var canToggleToPaid: Bool {
        // 未選択決済を含む場合は「済み」へ遷移させない
        item.isPaid || !item.includesUnselectedCard
    }
    private var canTapToggle: Bool {
        canToggleToPaid && !isToggling
    }

    var body: some View {
        HStack(spacing: 12) {
            // PAID/UNPAID バッジ
            Button(action: onToggle) {
                // セルと説明フッターで同じ見た目を再利用する
                PaymentStatusPill(isPaid: item.isPaid)
            }
            .disabled(!canTapToggle)
            .opacity(canTapToggle ? 1 : 0.4)
            // 切替操作の意味を読み上げでも伝える
            .accessibilityLabel(item.isPaid ? Text("payment.markUnpaid") : Text("payment.markPaid"))
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 8) {
                // 日付は2段表示にして中央揃えにする
                VStack(spacing: 0) {
                    Text(AppDateFormat.yearWeekdayText(item.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                    Text(AppDateFormat.monthDayText(item.date))
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(width: 76, alignment: .center)
                // 日付は優先表示して欠けにくくする
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                // 右側は1行表示を優先し、収まらない場合のみ2行表示へ切り替える
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(item.amount.currencyString())
                            .font(.body.monospacedDigit())
                            .foregroundStyle(item.amount < 0 ? Color.red : Color.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Text(item.amount.currencyString())
                                .font(.body.monospacedDigit())
                                .foregroundStyle(item.amount < 0 ? Color.red : Color.primary)
                                .lineLimit(1)
                                // 金額は最優先で欠けないようにする
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .layoutPriority(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Helper Views

private struct PaymentStatusPill: View {
    let isPaid: Bool

    var body: some View {
        // セル内の先頭は大きい矢印アイコンのみで状態を示す
        Image(systemName: isPaid ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
            .font(.title2.weight(.bold))
            .foregroundStyle(isPaid ? COLOR_PAID : COLOR_UNPAID)
            .frame(minWidth: 34, minHeight: 34)
    }
}

private extension E7payment {
    var includesUnselectedCard: Bool {
        // 1件でも決済手段未選択の請求があれば制御対象にする
        e2invoices.contains { $0.e1card == nil }
    }

    var hasAnySelectedCard: Bool {
        // 明細レコード側に決済手段が残っていれば、口座未選択として扱う
        if e2invoices.contains(where: { $0.e1card != nil }) {
            return true
        }
        return e2invoices
            .flatMap(\.e6parts)
            .contains { $0.e3record?.e1card != nil }
    }
}

private struct PaymentCombinedCard: View {
    let unpaidItems: [PaymentDisplayItem]
    let paidItems: [PaymentDisplayItem]
    let unpaidFilter: PaymentUnpaidFilter
    let onToggle: (PaymentDisplayItem) -> Void
    let togglingPaymentIDs: Set<String>
    let hasMorePaid: Bool
    let onLoadMorePaid: () -> Void
    let boundaryAnchorID: String
    let paidFirstRowAnchorID: String
    let windowDays: Int
    let onNavigateToDetail: () -> Void
    @State private var boundaryMidY: CGFloat = 0

    /// ViewBuilder 内の型推論負荷を下げるため、表示用の添字付き配列を事前に作る
    private var indexedPaidItems: [(offset: Int, element: PaymentDisplayItem)] {
        Array(paidItems.enumerated())
    }
    
    private var unpaidGrouped: PaymentUnpaidGrouped {
        PaymentUnpaidGrouped.build(from: unpaidItems, windowDays: windowDays)
    }

    /// 済み側の区切り線表示可否
    private func showsPaidDivider(after index: Int) -> Bool {
        index + 1 < paidItems.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if unpaidFilter == .upcoming {
                let indexedSections = Array(unpaidGrouped.sections.enumerated())
                ForEach(indexedSections, id: \.element.id) { sectionIndex, section in
                    if 0 < sectionIndex {
                        PaymentSectionSeparator()
                    }
                    if !section.items.isEmpty {
                        let indexedItems = Array(section.items.enumerated())
                        ForEach(indexedItems, id: \.element.id) { index, payment in
                            PaymentNavigationRow(
                                item: payment,
                                rowID: payment.id,
                                isToggling: togglingPaymentIDs.contains(payment.id),
                                onToggle: onToggle,
                                onNavigateToDetail: onNavigateToDetail
                            )
                            if index + 1 < section.items.count {
                                PaymentRowDivider()
                            }
                        }
                    }
                    // 空セクションは PaymentEmptyRow を省き、フッター（¥0）のみ表示する
                    PaymentPeriodFooter(
                        title: section.footerTitle,
                        amount: section.totalAmount
                    )
                }
            } else {
                if unpaidItems.isEmpty {
                    PaymentEmptyRow()
                } else {
                    let indexedItems = Array(unpaidItems.enumerated())
                    ForEach(indexedItems, id: \.element.id) { index, payment in
                        PaymentNavigationRow(
                            item: payment,
                            rowID: payment.id,
                            isToggling: togglingPaymentIDs.contains(payment.id),
                            onToggle: onToggle,
                            onNavigateToDetail: onNavigateToDetail
                        )
                        if index + 1 < unpaidItems.count {
                            PaymentRowDivider()
                        }
                    }
                }
            }

            // 境目を太線で区切り、上下にラベルを置いて文脈を維持する
            PaymentBoundaryMarker()
            // 動的な見た目と切り離した透明アンカーでスクロール位置を安定させる
            Color.clear
                .frame(height: 1)
                .id(boundaryAnchorID)

            if !paidItems.isEmpty {
                ForEach(indexedPaidItems, id: \.element.id) { index, payment in
                    PaymentNavigationRow(
                        item: payment,
                        rowID: index == 0 ? paidFirstRowAnchorID : payment.id,
                        isToggling: togglingPaymentIDs.contains(payment.id),
                        onToggle: onToggle,
                        onNavigateToDetail: onNavigateToDetail
                    )
                    if showsPaidDivider(after: index) {
                        PaymentRowDivider()
                    }
                }
                if hasMorePaid {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .onAppear {
                        onLoadMorePaid()
                    }
                }
            } else {
                // 済みが空のときは空セルを表示する
                PaymentEmptyRow()
                    .id(paidFirstRowAnchorID)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.95))
        )
        .overlay(
            GeometryReader { proxy in
                let cardHeight = proxy.size.height
                let splitY = min(max(boundaryMidY, 0), cardHeight)
                ZStack {
                    // 境界線より上側の外枠は未払色
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(COLOR_UNPAID, lineWidth: 1.5)
                        .mask(
                            Rectangle()
                                .frame(width: proxy.size.width, height: splitY)
                                .frame(maxHeight: .infinity, alignment: .top)
                        )
                    // 境界線より下側の外枠は払済み色
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(COLOR_PAID, lineWidth: 1.5)
                        .mask(
                            Rectangle()
                                .frame(width: proxy.size.width, height: max(cardHeight - splitY, 0))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        )
                }
            }
        )
        .coordinateSpace(name: "paymentCombinedCard")
        // 行が未払/済みの間を移る変化を自然に見せる
        .animation(.easeInOut(duration: 0.55), value: unpaidItems.map(\.id))
        .animation(.easeInOut(duration: 0.55), value: paidItems.map(\.id))
        .onPreferenceChange(PaymentBoundaryMidYPreferenceKey.self) { y in
            if y > 0 {
                boundaryMidY = y
            }
        }
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

private struct PaymentEmptyRow: View {
    var body: some View {
        HStack {
            Spacer()
            Text("label.empty")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

private struct PaymentNavigationRow: View {
    let item: PaymentDisplayItem
    let rowID: String
    let isToggling: Bool
    let onToggle: (PaymentDisplayItem) -> Void
    let onNavigateToDetail: () -> Void

    var body: some View {
        if let detailPayment = item.detailPayment {
            NavigationLink {
                InvoiceListView(payment: detailPayment)
                    .onAppear { onNavigateToDetail() }
            } label: {
                PaymentRow(item: item, isToggling: isToggling) {
                    onToggle(item)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .id(rowID)
        } else {
            NavigationLink {
                // 複数支払を束ねた行は、口座を出さない明細画面で開く
                InvoiceListView(displayItem: item)
                    .onAppear { onNavigateToDetail() }
            } label: {
                PaymentRow(item: item, isToggling: isToggling) {
                    onToggle(item)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .id(rowID)
        }
    }
}

private struct PaymentRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}

private struct PaymentBoundaryMarker: View {
    @Environment(\.colorScheme) private var colorScheme

    private var boundaryColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var edgeHighlightOpacity: Double {
        // 明るすぎないように、端の発色は抑えめにする
        colorScheme == .dark ? 0.44 : 0.26
    }

    private var labelColor: Color {
        // ダーク時のみラベル文字を見やすくする
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.secondary
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("payment.section.unpaidBeforeDebit")
                .font(.headline.weight(.semibold))
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            .background(
                // 上端の色をラベル帯に自然に引き込む
                LinearGradient(
                    colors: [COLOR_UNPAID.opacity(edgeHighlightOpacity * 0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // 境界線だけ明るくする
            Rectangle()
                .fill(boundaryColor)
                .frame(height: 2)
                .background(
                    // 境界線の位置を親へ伝える
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PaymentBoundaryMidYPreferenceKey.self,
                            value: proxy.frame(in: .named("paymentCombinedCard")).midY
                        )
                    }
                )

            Text("payment.section.paidAfterDebit")
                .font(.headline.weight(.semibold))
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .background(
                    // 下端の色をラベル帯に自然に引き込む
                    LinearGradient(
                        colors: [.clear, COLOR_PAID.opacity(edgeHighlightOpacity * 0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

private struct PaymentBoundaryMidYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

/// 未払集計の表示値
private struct PaymentUnpaidSummaries {
    let currentTitle: String
    let currentAmount: Decimal
    let nextTitle: String
    let nextAmount: Decimal
    let futureTitle: String
    let futureAmount: Decimal

    static func build(from payments: [E7payment], windowDays rawWindowDays: Int) -> PaymentUnpaidSummaries {
        let windowDays = max(1, min(rawWindowDays, 30))
        let sorted = payments.sorted { $0.date < $1.date }
        let today = Calendar.current.startOfDay(for: Date())

        // 起点は常に本日。データがなくても空集計を返す
        let firstRange  = windowRange(start: today, windowDays: windowDays)
        // 次の期間は現在期間の翌日から同じ幅で取る
        let secondStart = Calendar.current.date(byAdding: .day, value: 1, to: firstRange.upperBound) ?? firstRange.upperBound
        let secondRange = windowRange(start: secondStart, windowDays: windowDays)

        let currentAmount = sorted
            .filter { firstRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .reduce(Decimal.zero) { $0 + $1.sumAmount }
        let nextAmount = sorted
            .filter { secondRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .reduce(Decimal.zero) { $0 + $1.sumAmount }
        let futureAmount = sorted
            .filter { secondRange.upperBound < Calendar.current.startOfDay(for: $0.date) }
            .reduce(Decimal.zero) { $0 + $1.sumAmount }

        return PaymentUnpaidSummaries(
            currentTitle: localizedCurrentTitle(windowDays: windowDays),
            currentAmount: currentAmount,
            nextTitle: localizedNextTitle(windowDays: windowDays),
            nextAmount: nextAmount,
            futureTitle: localizedFutureTitle(),
            futureAmount: futureAmount
        )
    }

    /// 期間終端を含むため ClosedRange を返す
    static func windowRange(start: Date, windowDays: Int) -> ClosedRange<Date> {
        if windowDays == 30 {
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            return start...end
        }
        let end = Calendar.current.date(byAdding: .day, value: windowDays - 1, to: start) ?? start
        return start...end
    }

    static func localizedCurrentTitle(windowDays: Int) -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        if windowDays == 30 {
            return isJapanese ? "1ヶ月の引き落とし合計" : "Current 1-Month Total"
        }
        return isJapanese ? "\(windowDays)日間の引き落とし合計" : "Current \(windowDays)-Day Total"
    }

    static func localizedNextTitle(windowDays: Int) -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        if windowDays == 30 {
            return isJapanese ? "次の1ヶ月の引き落とし合計" : "Next 1-Month Total"
        }
        return isJapanese ? "次の\(windowDays)日間の引き落とし合計" : "Next \(windowDays)-Day Total"
    }

    static func localizedFutureTitle() -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        return isJapanese ? "将来の引き落とし合計" : "Future Total"
    }

    static func localizedCurrentSummaryTitle(windowDays: Int) -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        if windowDays == 30 {
            return isJapanese ? "直近1ヶ月合計" : "Recent 1-Month Total"
        }
        return isJapanese ? "直近\(windowDays)日合計" : "Recent \(windowDays)-Day Total"
    }

    static func localizedNextSummaryTitle(windowDays: Int) -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        if windowDays == 30 {
            return isJapanese ? "次の1ヶ月合計" : "Next 1-Month Total"
        }
        return isJapanese ? "次の\(windowDays)日合計" : "Next \(windowDays)-Day Total"
    }
}

/// 未払を3期間に分ける表示モデル
private struct PaymentUnpaidGrouped {
    struct Section: Identifiable {
        let id: String
        let footerTitle: String
        let items: [PaymentDisplayItem]
        let totalAmount: Decimal
    }

    let sections: [Section]

    static func build(from payments: [PaymentDisplayItem], windowDays rawWindowDays: Int) -> PaymentUnpaidGrouped {
        let windowDays = max(1, min(rawWindowDays, 30))
        let sorted = payments.sorted { $0.date < $1.date }
        let today = Calendar.current.startOfDay(for: Date())

        // 起点は常に本日（PaymentUnpaidSummaries と一致させる）
        let firstRange  = PaymentUnpaidSummaries.windowRange(start: today, windowDays: windowDays)
        let secondStart = Calendar.current.date(byAdding: .day, value: 1, to: firstRange.upperBound) ?? firstRange.upperBound
        let secondRange = PaymentUnpaidSummaries.windowRange(start: secondStart, windowDays: windowDays)
        let futureLowerBound = Calendar.current.date(byAdding: .day, value: 1, to: secondRange.upperBound) ?? secondRange.upperBound

        // 期間が重複しないよう、直近/次/将来を排他的な範囲で分割する
        let currentItems = sorted
            .filter { firstRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .sorted { $1.date < $0.date }
        let nextItems = sorted
            .filter { secondRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .sorted { $1.date < $0.date }
        let futureItems = sorted
            .filter { futureLowerBound <= Calendar.current.startOfDay(for: $0.date) }
            .sorted { $1.date < $0.date }

        let currentTotal = currentItems.reduce(Decimal.zero) { $0 + $1.amount }
        let nextTotal    = nextItems.reduce(Decimal.zero)    { $0 + $1.amount }
        let futureTotal  = futureItems.reduce(Decimal.zero)  { $0 + $1.amount }

        // 3セクション常に表示（空でも ¥0 フッターで期間の状況を示す）
        return PaymentUnpaidGrouped(
            sections: [
                Section(
                    id: "future",
                    footerTitle: PaymentUnpaidSummaries.localizedFutureTitle(),
                    items: futureItems,
                    totalAmount: futureTotal
                ),
                Section(
                    id: "next",
                    footerTitle: PaymentUnpaidSummaries.localizedNextSummaryTitle(windowDays: windowDays),
                    items: nextItems,
                    totalAmount: nextTotal
                ),
                Section(
                    id: "current",
                    footerTitle: PaymentUnpaidSummaries.localizedCurrentSummaryTitle(windowDays: windowDays),
                    items: currentItems,
                    totalAmount: currentTotal
                ),
            ]
        )
    }
}

private struct PaymentSectionSeparator: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [COLOR_UNPAID.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 10)
            .padding(.top, 2)
            .padding(.bottom, 6)
    }
}

private struct PaymentPeriodFooter: View {
    let title: String
    let amount: Decimal

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(amount.currencyString())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(COLOR_UNPAID)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
