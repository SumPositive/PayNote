import SwiftUI
import SwiftData

struct PaymentListView: View {
    @Query(sort: \E7payment.date, order: .reverse) private var allPayments: [E7payment]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner
    @State private var didInitialScroll = false
    @State private var undoAction: PaymentToggleUndoAction?
    @State private var paidVisibleCount = 0
    private let pageSize = 100
    private let paidFirstRowAnchorID = "payment-paid-first-row-anchor"

    private var allGroups: [PaymentDisplayGroup] {
        allPayments.flatMap(\.displayGroups)
    }

    private var unpaidGroups: [PaymentDisplayGroup] {
        allGroups.filter { !$0.isPaid }
    }

    private var allPaidGroups: [PaymentDisplayGroup] {
        allGroups.filter(\.isPaid)
    }

    private var paidGroups: [PaymentDisplayGroup] {
        Array(allPaidGroups.prefix(paidVisibleCount))
    }

    private var hasMorePaid: Bool {
        paidVisibleCount < allPaidGroups.count
    }

    private var hasAnyPayments: Bool {
        !allGroups.isEmpty
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
                                unpaidPayments: unpaidGroups,
                                paidPayments: paidGroups,
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
                        if paidVisibleCount == 0 {
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
        .onChange(of: allGroups.map(\.id)) { _, _ in
            // 表示グループが変わったら、済み側の表示件数だけ整える
            resetAndLoadPaid()
        }
    }

    private func scrollToPaidTopIfNeeded(proxy: ScrollViewProxy) {
        if didInitialScroll {
            return
        }
        // 未払が少ない場合は、初期スクロールしなくても済み先頭が見える
        if unpaidGroups.count <= 4 {
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

    private func togglePaid(_ group: PaymentDisplayGroup) {
        let previousIsPaid = group.isPaid
        let nextIsPaid = !previousIsPaid
        // 決済手段未選択を含む支払は、未払→済みへの更新を禁止する
        if !previousIsPaid && group.includesUnselectedCard {
            return
        }
        applyPaidState(group, isPaid: nextIsPaid)
        // トグル後に取り消しアクションを出す
        showUndoAction(group: group, previousIsPaid: previousIsPaid)
    }

    private func undoToggle() {
        guard let action = undoAction else {
            return
        }
        applyPaidState(action.group, isPaid: action.previousIsPaid)
        undoAction = nil
    }

    private func showUndoAction(group: PaymentDisplayGroup, previousIsPaid: Bool) {
        let token = UUID()
        undoAction = PaymentToggleUndoAction(
            group: group,
            previousIsPaid: previousIsPaid,
            movedToPaid: group.isPaid,
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

    private func applyPaidState(_ group: PaymentDisplayGroup, isPaid: Bool) {
        // 未払/済みの変更はサービス層でまとめて保存する
        try? RecordService.setInvoicesPaid(
            group.invoices,
            isPaid: isPaid,
            context: context
        )
        // 済みセクションは表示件数だけ持っているため、変更後に件数を整える
        resetAndLoadPaid()
    }

    private func resetAndLoadPaid() {
        paidVisibleCount = min(pageSize, allPaidGroups.count)
    }

    private func loadMorePaidIfNeeded() {
        if !hasMorePaid {
            return
        }
        paidVisibleCount = min(paidVisibleCount + pageSize, allPaidGroups.count)
    }
}

// MARK: - Row

private struct PaymentRow: View {
    let group: PaymentDisplayGroup
    let onToggle: () -> Void
    private var canToggleToPaid: Bool {
        // 未選択決済を含む場合は「済み」へ遷移させない
        group.isPaid || !group.includesUnselectedCard
    }

    var body: some View {
        HStack(spacing: 12) {
            // PAID/UNPAID バッジ
            Button(action: onToggle) {
                // セルと説明フッターで同じ見た目を再利用する
                PaymentStatusPill(isPaid: group.isPaid)
            }
            .disabled(!canToggleToPaid)
            .opacity(canToggleToPaid ? 1 : 0.4)
            // 切替操作の意味を読み上げでも伝える
            .accessibilityLabel(group.isPaid ? Text("payment.markUnpaid") : Text("payment.markPaid"))
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                // 日付は2段表示にして中央揃えにする
                VStack(spacing: 0) {
                    Text(AppDateFormat.yearWeekdayText(group.payment.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(AppDateFormat.monthDayText(group.payment.date))
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(width: 76, alignment: .center)
                // 日付は優先表示して欠けにくくする
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                Text(group.bankNameText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // 省略は口座名側で受ける
                    .layoutPriority(0)
            }
            .layoutPriority(1)

            Spacer()

            Text(group.sumAmount.currencyString())
                .font(.body.monospacedDigit())
                .foregroundStyle(group.isPaid ? COLOR_PAID : COLOR_UNPAID)
                .lineLimit(1)
                // 金額は最優先で欠けないようにする
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(3)
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

private struct PaymentCombinedCard: View {
    let unpaidPayments: [PaymentDisplayGroup]
    let paidPayments: [PaymentDisplayGroup]
    let onToggle: (PaymentDisplayGroup) -> Void
    let hasMorePaid: Bool
    let onLoadMorePaid: () -> Void
    let paidFirstRowAnchorID: String
    @State private var boundaryMidY: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if !unpaidPayments.isEmpty {
                ForEach(Array(unpaidPayments.enumerated()), id: \.element.id) { index, payment in
                    NavigationLink {
                        InvoiceListView(group: payment)
                    } label: {
                        PaymentRow(group: payment) {
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
                        InvoiceListView(group: payment)
                    } label: {
                        PaymentRow(group: payment) {
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
    let group: PaymentDisplayGroup
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
