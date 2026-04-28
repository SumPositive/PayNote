import SwiftUI
import SwiftData

struct PaymentListView: View {
    @Query(sort: \E7payment.date, order: .reverse) private var allPayments: [E7payment]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner
    @AppStorage(AppStorageKey.paymentWindowDays) private var paymentWindowDays = 7
    @State private var didInitialScroll = false
    @State private var paidVisibleCount = 0
    @State private var togglingPaymentIDs: Set<String> = []
    private let paymentMoveAnimation = Animation.easeInOut(duration: 0.55)
    private let pageSize = 100
    private let paidFirstRowAnchorID = "payment-paid-first-row-anchor"

    private var unpaidPayments: [E7payment] {
        allPayments.filter { !$0.isPaid }
    }

    private var allPaidPayments: [E7payment] {
        allPayments.filter(\.isPaid)
    }

    private var paidPayments: [E7payment] {
        Array(allPaidPayments.prefix(paidVisibleCount))
    }

    private var hasMorePaid: Bool {
        paidVisibleCount < allPaidPayments.count
    }

    private var hasAnyPayments: Bool {
        !allPayments.isEmpty
    }

    var body: some View {
        Group {
            if !hasAnyPayments {
                ContentUnavailableView("label.empty", systemImage: "calendar.badge.clock")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if userLevel == .beginner {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("payment.beginner.title")
                                        .font(.subheadline.weight(.semibold))
                                    // 文とアイコン付き操作文を分け、改行位置を自然にする
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("payment.beginner.line1")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .foregroundStyle(COLOR_UNPAID)
                                                .font(.caption.weight(.bold))
                                            Text("payment.beginner.line2")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("payment.beginner.line3")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .foregroundStyle(COLOR_PAID)
                                                .font(.caption.weight(.bold))
                                            Text("payment.beginner.line4")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            PaymentCombinedCard(
                                unpaidPayments: unpaidPayments,
                                paidPayments: paidPayments,
                                onToggle: togglePaid,
                                togglingPaymentIDs: togglingPaymentIDs,
                                hasMorePaid: hasMorePaid,
                                onLoadMorePaid: loadMorePaidIfNeeded,
                                paidFirstRowAnchorID: paidFirstRowAnchorID,
                                windowDays: paymentWindowDays
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .onAppear {
                        if paidVisibleCount == 0 {
                            resetAndLoadPaid()
                        }
                        scrollToPaidTopIfNeeded(proxy: proxy)
                    }
                }
            }
        }
        .scalableNavigationTitle("payment.list.title")
        .onChange(of: allPayments.map(\.id)) { _, _ in
            // 表示集合が変わったら、済み側の表示件数だけ整える
            resetAndLoadPaid()
        }
    }

    private func scrollToPaidTopIfNeeded(proxy: ScrollViewProxy) {
        if didInitialScroll {
            return
        }
        // 未払が少ない場合は、初期スクロールしなくても済み先頭が見える
        if unpaidPayments.count <= 4 {
            didInitialScroll = true
            return
        }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                // 済みの先頭（データなしを含む）が必ず見える位置へ寄せる
                proxy.scrollTo(paidFirstRowAnchorID, anchor: .bottom)
            }
            didInitialScroll = true
        }
    }

    private func togglePaid(_ payment: E7payment) {
        // 連打で同じ支払を二重更新しないよう、短時間ロックする
        if togglingPaymentIDs.contains(payment.id) {
            return
        }
        let previousIsPaid = payment.isPaid
        let nextIsPaid = !previousIsPaid
        // 決済手段未選択を含む支払は、未払→済みへの更新を禁止する
        if !previousIsPaid && payment.includesUnselectedCard {
            return
        }
        togglingPaymentIDs.insert(payment.id)
        applyPaidState(payment, isPaid: nextIsPaid)
        Task { @MainActor in
            // 画面更新が落ち着くまで短くロックを残す
            try? await Task.sleep(nanoseconds: 400_000_000)
            togglingPaymentIDs.remove(payment.id)
        }
    }

    private func applyPaidState(_ payment: E7payment, isPaid: Bool) {
        withAnimation(paymentMoveAnimation) {
            // 未払/済みの変更はサービス層でまとめて保存する
            try? RecordService.setInvoicesPaid(
                payment.e2invoices,
                isPaid: isPaid,
                context: context
            )
            // 済みセクションは表示件数だけ持っているため、変更後に件数を整える
            resetAndLoadPaid()
        }
    }

    private func resetAndLoadPaid() {
        paidVisibleCount = min(pageSize, allPaidPayments.count)
    }

    private func loadMorePaidIfNeeded() {
        if !hasMorePaid {
            return
        }
        paidVisibleCount = min(paidVisibleCount + pageSize, allPaidPayments.count)
    }
}

// MARK: - Row

private struct PaymentRow: View {
    let payment: E7payment
    let isToggling: Bool
    let onToggle: () -> Void
    private var canToggleToPaid: Bool {
        // 未選択決済を含む場合は「済み」へ遷移させない
        payment.isPaid || !payment.includesUnselectedCard
    }

    private var canTapToggle: Bool {
        canToggleToPaid && !isToggling
    }

    private var bankNameText: String {
        if payment.includesUnselectedCard {
            let cardLabel = NSLocalizedString("record.field.card", comment: "")
            let noSelection = NSLocalizedString("label.noSelection", comment: "")
            return "\(cardLabel) \(noSelection)"
        }
        if let bankName = payment.e8bank?.zName, !bankName.isEmpty {
            return bankName
        }
        return NSLocalizedString("payment.bank.noSelection", comment: "")
    }

    var body: some View {
        HStack(spacing: 12) {
            // PAID/UNPAID バッジ
            Button(action: onToggle) {
                // セルと説明フッターで同じ見た目を再利用する
                PaymentStatusPill(isPaid: payment.isPaid)
            }
            .disabled(!canTapToggle)
            .opacity(canTapToggle ? 1 : 0.4)
            // 切替操作の意味を読み上げでも伝える
            .accessibilityLabel(payment.isPaid ? Text("payment.markUnpaid") : Text("payment.markPaid"))
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 8) {
                // 日付は2段表示にして中央揃えにする
                VStack(spacing: 0) {
                    Text(AppDateFormat.yearWeekdayText(payment.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                    Text(AppDateFormat.monthDayText(payment.date))
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
                        Text(bankNameText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(payment.sumAmount.currencyString())
                            .font(.body.monospacedDigit())
                            .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bankNameText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Text(payment.sumAmount.currencyString())
                                .font(.body.monospacedDigit())
                                .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
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
            .symbolRenderingMode(.hierarchical)
        .foregroundStyle(isPaid ? COLOR_PAID : COLOR_UNPAID)
            .frame(minWidth: 34, minHeight: 34)
    }
}

private extension E7payment {
    var includesUnselectedCard: Bool {
        // 1件でも決済手段未選択の請求があれば制御対象にする
        e2invoices.contains { $0.e1card == nil }
    }
}

private struct PaymentCombinedCard: View {
    let unpaidPayments: [E7payment]
    let paidPayments: [E7payment]
    let onToggle: (E7payment) -> Void
    let togglingPaymentIDs: Set<String>
    let hasMorePaid: Bool
    let onLoadMorePaid: () -> Void
    let paidFirstRowAnchorID: String
    let windowDays: Int
    @State private var boundaryMidY: CGFloat = 0

    /// ViewBuilder 内の型推論負荷を下げるため、表示用の添字付き配列を事前に作る
    private var indexedPaidPayments: [(offset: Int, element: E7payment)] {
        Array(paidPayments.enumerated())
    }
    
    private var unpaidGrouped: PaymentUnpaidGrouped {
        PaymentUnpaidGrouped.build(from: unpaidPayments, windowDays: windowDays)
    }

    /// 済み側の区切り線表示可否
    private func showsPaidDivider(after index: Int) -> Bool {
        index + 1 < paidPayments.count
    }

    var body: some View {
        VStack(spacing: 0) {
            let indexedSections = Array(unpaidGrouped.sections.enumerated())
            ForEach(indexedSections, id: \.element.id) { sectionIndex, section in
                if 0 < sectionIndex {
                    PaymentSectionSeparator()
                }
                if section.items.isEmpty {
                    PaymentEmptyRow()
                } else {
                    let indexedItems = Array(section.items.enumerated())
                    ForEach(indexedItems, id: \.element.id) { index, payment in
                        PaymentNavigationRow(
                            payment: payment,
                            rowID: payment.id,
                            isToggling: togglingPaymentIDs.contains(payment.id),
                            onToggle: onToggle
                        )
                        if index + 1 < section.items.count {
                            PaymentRowDivider()
                        }
                    }
                }
                PaymentPeriodFooter(
                    title: section.footerTitle,
                    amount: section.totalAmount
                )
            }

            // 境目を太線で区切り、上下にラベルを置いて文脈を維持する
            PaymentBoundaryMarker()

            if !paidPayments.isEmpty {
                ForEach(indexedPaidPayments, id: \.element.id) { index, payment in
                    PaymentNavigationRow(
                        payment: payment,
                        rowID: index == 0 ? paidFirstRowAnchorID : payment.id,
                        isToggling: togglingPaymentIDs.contains(payment.id),
                        onToggle: onToggle
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
        .animation(.easeInOut(duration: 0.55), value: unpaidPayments.map(\.id))
        .animation(.easeInOut(duration: 0.55), value: paidPayments.map(\.id))
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
    let payment: E7payment
    let rowID: String
    let isToggling: Bool
    let onToggle: (E7payment) -> Void

    var body: some View {
        NavigationLink {
            InvoiceListView(payment: payment)
        } label: {
            PaymentRow(payment: payment, isToggling: isToggling) {
                onToggle(payment)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .id(rowID)
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
        colorScheme == .dark ? Color.black.opacity(0.9) : Color.white
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
        let allDates = sorted.map { Calendar.current.startOfDay(for: $0.date) }

        let firstAnchor = allDates.first { today <= $0 } ?? allDates.first
        guard let firstAnchor else {
            return PaymentUnpaidSummaries(
                currentTitle: localizedCurrentTitle(windowDays: windowDays),
                currentAmount: .zero,
                nextTitle: localizedNextTitle(windowDays: windowDays),
                nextAmount: .zero,
                futureTitle: localizedFutureTitle(),
                futureAmount: .zero
            )
        }

        let secondAnchor = allDates.first { firstAnchor < $0 }
        let firstRange = windowRange(start: firstAnchor, windowDays: windowDays)
        let secondRange = secondAnchor.map { windowRange(start: $0, windowDays: windowDays) }

        let currentAmount = sorted
            .filter { firstRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .reduce(Decimal.zero) { partialResult, payment in
                partialResult + payment.sumAmount
            }
        let nextAmount = sorted
            .filter { payment in
                guard let secondRange else { return false }
                return secondRange.contains(Calendar.current.startOfDay(for: payment.date))
            }
            .reduce(Decimal.zero) { partialResult, payment in
                partialResult + payment.sumAmount
            }

        let futureBoundary = (secondRange?.upperBound ?? firstRange.upperBound)
        let futureAmount = sorted
            .filter { futureBoundary < Calendar.current.startOfDay(for: $0.date) }
            .reduce(Decimal.zero) { partialResult, payment in
                partialResult + payment.sumAmount
            }

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
            return isJapanese ? "1ヶ月の引き落とし計" : "Current 1-Month Debit Total"
        }
        return isJapanese ? "\(windowDays)日間の引き落とし計" : "Current \(windowDays)-Day Debit Total"
    }

    static func localizedNextTitle(windowDays: Int) -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        if windowDays == 30 {
            return isJapanese ? "次の1ヶ月の引き落とし計" : "Next 1-Month Debit Total"
        }
        return isJapanese ? "次の\(windowDays)日間の引き落とし計" : "Next \(windowDays)-Day Debit Total"
    }

    static func localizedFutureTitle() -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        return isJapanese ? "将来の引き落とし計" : "Future Debit Total"
    }

    static func localizedCurrentSummaryTitle() -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        return isJapanese ? "直近の引き落とし計" : "Current Debit Total"
    }

    static func localizedNextSummaryTitle() -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        return isJapanese ? "次の引き落とし計" : "Next Debit Total"
    }
}

/// 未払を3期間に分ける表示モデル
private struct PaymentUnpaidGrouped {
    struct Section: Identifiable {
        let id: String
        let footerTitle: String
        let items: [E7payment]
        let totalAmount: Decimal
    }

    let sections: [Section]

    static func build(from payments: [E7payment], windowDays rawWindowDays: Int) -> PaymentUnpaidGrouped {
        let windowDays = max(1, min(rawWindowDays, 30))
        let sorted = payments.sorted { $0.date < $1.date }
        let today = Calendar.current.startOfDay(for: Date())
        let allDates = sorted.map { Calendar.current.startOfDay(for: $0.date) }
        let firstAnchor = allDates.first { today <= $0 } ?? allDates.first

        guard let firstAnchor else {
            return PaymentUnpaidGrouped(
                sections: [
                    Section(id: "current", footerTitle: PaymentUnpaidSummaries.localizedCurrentSummaryTitle(), items: [], totalAmount: .zero),
                    Section(id: "next", footerTitle: PaymentUnpaidSummaries.localizedNextTitle(windowDays: windowDays), items: [], totalAmount: .zero),
                    Section(id: "future", footerTitle: PaymentUnpaidSummaries.localizedFutureTitle(), items: [], totalAmount: .zero),
                ]
            )
        }

        let secondAnchor = allDates.first { firstAnchor < $0 }
        let firstRange = PaymentUnpaidSummaries.windowRange(start: firstAnchor, windowDays: windowDays)
        let secondRange = secondAnchor.map { PaymentUnpaidSummaries.windowRange(start: $0, windowDays: windowDays) }
        let nextRangeLowerBound = Calendar.current.date(byAdding: .day, value: 1, to: firstRange.upperBound) ?? firstRange.upperBound
        let futureLowerBound = Calendar.current.date(byAdding: .day, value: 1, to: (secondRange?.upperBound ?? firstRange.upperBound)) ?? (secondRange?.upperBound ?? firstRange.upperBound)

        // 期間が重複しないよう、直近/次/将来を排他的な範囲で分割する
        let currentItems = sorted
            .filter { firstRange.contains(Calendar.current.startOfDay(for: $0.date)) }
            .sorted { $1.date < $0.date }
        let nextItems = sorted
            .filter { payment in
                let date = Calendar.current.startOfDay(for: payment.date)
                if let secondRange {
                    if date < nextRangeLowerBound {
                        return false
                    }
                    return date <= secondRange.upperBound
                }
                return nextRangeLowerBound <= date
            }
            .sorted { $1.date < $0.date }
        let futureItems = sorted
            .filter { futureLowerBound <= Calendar.current.startOfDay(for: $0.date) }
            .sorted { $1.date < $0.date }

        let currentTotal = currentItems.reduce(Decimal.zero) { partialResult, payment in
            partialResult + payment.sumAmount
        }
        let nextTotal = nextItems.reduce(Decimal.zero) { partialResult, payment in
            partialResult + payment.sumAmount
        }
        let futureTotal = futureItems.reduce(Decimal.zero) { partialResult, payment in
            partialResult + payment.sumAmount
        }

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
                    footerTitle: PaymentUnpaidSummaries.localizedNextSummaryTitle(),
                    items: nextItems,
                    totalAmount: nextTotal
                ),
                Section(
                    id: "current",
                    footerTitle: PaymentUnpaidSummaries.localizedCurrentSummaryTitle(),
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
