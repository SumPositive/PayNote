import SwiftUI
import SwiftData

struct PaymentListView: View {
    @Query(filter: #Predicate<E7payment> { !$0.isPaid },
           sort: \E7payment.date, order: .reverse) private var unpaidPayments: [E7payment]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner
    @State private var didInitialScroll = false
    @State private var undoAction: PaymentToggleUndoAction?
    @State private var paidPayments: [E7payment] = []
    @State private var paidPage = 0
    @State private var hasMorePaid = true
    @State private var isLoadingPaid = false
    @State private var hasAnyPayments = true
    private let pageSize = 100
    private let paidFirstRowAnchorID = "payment-paid-first-row-anchor"

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
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("payment.beginner.line1")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(COLOR_UNPAID)
                                            .font(.caption.weight(.bold))
                                        Text("payment.beginner.line2")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("payment.beginner.line3")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundStyle(COLOR_PAID)
                                            .font(.caption.weight(.bold))
                                        Text("payment.beginner.line4")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            PaymentCombinedCard(
                                unpaidPayments: unpaidPayments,
                                paidPayments: paidPayments,
                                onToggle: togglePaid,
                                hasMorePaid: hasMorePaid,
                                onLoadMorePaid: loadMorePaidIfNeeded,
                                paidFirstRowAnchorID: paidFirstRowAnchorID
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .onAppear {
                        // 旧請求の残骸（明細ゼロ）を先に掃除する
                        RecordService.cleanupOrphanBilling(context: context)
                        // 旧仕様で請求データが未作成の「決済手段未選択」明細を補完する
                        ensureUnselectedRecordsScheduled()
                        refreshHasAnyPayments()
                        if paidPayments.isEmpty {
                            resetAndLoadPaid()
                        }
                        scrollToPaidTopIfNeeded(proxy: proxy)
                    }
                }
            }
        }
        .scalableNavigationTitle("payment.list.title")
        .overlay(alignment: .bottom) {
            if let action = undoAction {
                PaymentUndoToast(action: action) {
                    undoToggle()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: undoAction != nil)
        .onChange(of: unpaidPayments.map(\.id)) { _, _ in
            // 支払状態変更で未払集合が変わったら、済み側ページを再読込する
            refreshHasAnyPayments()
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
        let previousIsPaid = payment.isPaid
        let nextIsPaid = !previousIsPaid
        // 決済手段未選択を含む支払は、未払→済みへの更新を禁止する
        if !previousIsPaid && payment.includesUnselectedCard {
            return
        }
        applyPaidState(payment, isPaid: nextIsPaid)
        // トグル後に取り消しアクションを出す
        showUndoAction(payment: payment, previousIsPaid: previousIsPaid)
    }

    private func undoToggle() {
        guard let action = undoAction else {
            return
        }
        applyPaidState(action.payment, isPaid: action.previousIsPaid)
        undoAction = nil
    }

    private func showUndoAction(payment: E7payment, previousIsPaid: Bool) {
        let token = UUID()
        undoAction = PaymentToggleUndoAction(
            payment: payment,
            previousIsPaid: previousIsPaid,
            movedToPaid: payment.isPaid,
            token: token
        )
        Task { @MainActor in
            // 一定時間で自動的に閉じる
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if undoAction?.token == token {
                undoAction = nil
            }
        }
    }

    private func applyPaidState(_ payment: E7payment, isPaid: Bool) {
        payment.isPaid = isPaid
        // すべての子 invoice に伝播
        for inv in payment.e2invoices {
            inv.isPaid = isPaid
            if isPaid, let card = inv.e1card {
                // repeat が必要なレコードを生成
                for part in inv.e6parts {
                    if let record = part.e3record, record.nRepeat > 0 {
                        let existsNext = record.e1card?.e3records.contains(where: {
                            Calendar.current.isDate($0.dateUse,
                                equalTo: Calendar.current.date(byAdding: .month,
                                    value: Int(record.nRepeat), to: record.dateUse) ?? Date(),
                                toGranularity: .month)
                        }) ?? false
                        if !existsNext {
                            RecordService.makeRepeatRecord(from: record, context: context)
                        }
                    }
                }
                RecordService.recalculateCard(card)
            }
        }
        // 済みセクションはページングしているため、変更後は再読込する
        resetAndLoadPaid()
    }

    private func resetAndLoadPaid() {
        paidPage = 0
        hasMorePaid = true
        paidPayments = []
        loadMorePaidIfNeeded()
    }

    private func loadMorePaidIfNeeded() {
        if isLoadingPaid || !hasMorePaid {
            return
        }
        isLoadingPaid = true
        defer { isLoadingPaid = false }

        var descriptor = FetchDescriptor<E7payment>(
            predicate: #Predicate<E7payment> { $0.isPaid },
            sortBy: [SortDescriptor(\E7payment.date, order: .reverse)]
        )
        descriptor.fetchOffset = paidPage * pageSize
        descriptor.fetchLimit = pageSize

        let fetched = (try? context.fetch(descriptor)) ?? []
        paidPayments.append(contentsOf: fetched)
        paidPage += 1
        hasMorePaid = pageSize <= fetched.count
    }

    private func refreshHasAnyPayments() {
        // 未払が0件でも済みがあれば一覧を表示する
        let count = (try? context.fetchCount(FetchDescriptor<E7payment>())) ?? 0
        hasAnyPayments = 0 < count
    }

    private func ensureUnselectedRecordsScheduled() {
        // 既存データ向け: 決済手段未選択かつ請求パーツ未作成の明細だけを対象にする
        let descriptor = FetchDescriptor<E3record>(
            predicate: #Predicate<E3record> { $0.e1card == nil && $0.e6parts.isEmpty }
        )
        let targets = (try? context.fetch(descriptor)) ?? []
        if targets.isEmpty {
            return
        }
        for record in targets {
            RecordService.save(record, context: context)
        }
    }
}

// MARK: - Row

private struct PaymentRow: View {
    let payment: E7payment
    let onToggle: () -> Void
    private var canToggleToPaid: Bool {
        // 未選択決済を含む場合は「済み」へ遷移させない
        payment.isPaid || !payment.includesUnselectedCard
    }
    private var bankNameText: String {
        // 決済手段未選択の請求が含まれる場合は、口座ではなく決済手段未選択と表示する
        if payment.includesUnselectedCard {
            let cardLabel = NSLocalizedString("record.field.card", comment: "")
            let noSelection = NSLocalizedString("label.noSelection", comment: "")
            return "\(cardLabel) \(noSelection)"
        }
        // 請求書に紐づく口座名の先頭を表示する（未設定時は共通ラベル）
        if let name = payment.e2invoices
            .compactMap({ $0.e1card?.e8bank?.zName })
            .first(where: { !$0.isEmpty }) {
            return name
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
            .disabled(!canToggleToPaid)
            .opacity(canToggleToPaid ? 1 : 0.4)
            // 切替操作の意味を読み上げでも伝える
            .accessibilityLabel(payment.isPaid ? Text("payment.markUnpaid") : Text("payment.markPaid"))
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                // 日付は2段表示にして中央揃えにする
                VStack(spacing: 0) {
                    Text(AppDateFormat.yearWeekdayText(payment.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(AppDateFormat.monthDayText(payment.date))
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(width: 76, alignment: .center)
                // 日付は優先表示して欠けにくくする
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                Text(bankNameText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // 省略は口座名側で受ける
                    .layoutPriority(0)
            }
            .layoutPriority(1)

            Spacer()

            Text(payment.sumAmount.currencyString())
                .font(.body.monospacedDigit())
                .foregroundStyle(payment.isPaid ? COLOR_PAID : COLOR_UNPAID)
                .lineLimit(1)
                // 金額は最優先で欠けないようにする
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(3)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private extension E7payment {
    var includesUnselectedCard: Bool {
        // 1件でも決済手段未選択の請求があれば制御対象にする
        e2invoices.contains { $0.e1card == nil }
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

private struct PaymentCombinedCard: View {
    let unpaidPayments: [E7payment]
    let paidPayments: [E7payment]
    let onToggle: (E7payment) -> Void
    let hasMorePaid: Bool
    let onLoadMorePaid: () -> Void
    let paidFirstRowAnchorID: String
    @State private var boundaryMidY: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if !unpaidPayments.isEmpty {
                ForEach(Array(unpaidPayments.enumerated()), id: \.element.id) { index, payment in
                    NavigationLink {
                        InvoiceListView(payment: payment)
                    } label: {
                        PaymentRow(payment: payment) {
                            onToggle(payment)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .id(payment.id)
                    if index + 1 < unpaidPayments.count {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            } else {
                // 未払が空のときは空セルを表示する
                PaymentEmptyRow()
            }

            // 境目を太線で区切り、上下にラベルを置いて文脈を維持する
            PaymentBoundaryMarker()

            if !paidPayments.isEmpty {
                ForEach(Array(paidPayments.enumerated()), id: \.element.id) { index, payment in
                    NavigationLink {
                        InvoiceListView(payment: payment)
                    } label: {
                        PaymentRow(payment: payment) {
                            onToggle(payment)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .id(index == 0 ? paidFirstRowAnchorID : payment.id)
                    if index + 1 < paidPayments.count {
                        Divider()
                            .padding(.leading, 12)
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

private struct PaymentBoundaryMarker: View {
    @Environment(\.colorScheme) private var colorScheme

    private var boundaryColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.9) : Color.white
    }

    private var edgeHighlightOpacity: Double {
        // 明るすぎないように、端の発色は抑えめにする
        colorScheme == .dark ? 0.44 : 0.26
    }

    private var edgeGradientHeight: CGFloat {
        // グラデーションが分かる最小限の高さ
        12
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

private struct PaymentToggleUndoAction {
    let payment: E7payment
    let previousIsPaid: Bool
    let movedToPaid: Bool
    let token: UUID
}

private struct PaymentUndoToast: View {
    let action: PaymentToggleUndoAction
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.movedToPaid ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(action.movedToPaid ? COLOR_PAID : COLOR_UNPAID)
            Text(action.movedToPaid ? "payment.toast.movedToPaid" : "payment.toast.movedToUnpaid")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 6)
            Button("button.undo") {
                onUndo()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
