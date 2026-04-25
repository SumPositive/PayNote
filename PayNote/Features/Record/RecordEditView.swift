import SwiftUI
import SwiftData

// MARK: - Mode

enum RecordEditMode {
    case addNew
    case edit(E3record)
}

extension RecordEditMode: Equatable {
    static func == (lhs: RecordEditMode, rhs: RecordEditMode) -> Bool {
        switch (lhs, rhs) {
        case (.addNew, .addNew): true
        case (.edit(let a), .edit(let b)): a.id == b.id
        default: false
        }
    }
}

// MARK: - View

struct RecordEditView: View {
    let mode: RecordEditMode
    var onSaved: (() -> Void)? = nil

    @Environment(\.modelContext)  private var context
    @Environment(\.dismiss)       private var dismiss
    @Query(sort: \E1card.nRow)    private var cards: [E1card]
    @Query(sort: \E3record.dateUse, order: .reverse) private var pastRecords: [E3record]
    @Query                        private var categories: [E5category]

    @AppStorage(AppStorageKey.enableInstallment) private var enableInstallment = false
    @AppStorage(AppStorageKey.afterSaveAction)   private var afterSaveAction: AfterSaveAction = .goBack

    @State private var dateUse:    Date     = Date()
    @State private var zName:      String   = ""
    @State private var zNote:      String   = ""
    @State private var nAmount:    Decimal  = 0
    @State private var payType:    PayType  = .lumpSum
    @State private var nRepeat:    Int16    = 0
    @State private var selectedCard:        E1card?
    @State private var selectedCategories:  [E5category] = []

    @State private var showAmountPad      = false
    @State private var showDatePicker     = false
    @State private var showCardPicker     = false
    @State private var showCategoryPicker = false
    @State private var showRepeatPicker   = false
    @State private var savedBanner        = false
    @State private var hasInitialized     = false
    @State private var initialDraft: DraftState?
    @FocusState private var isUsePointFocused: Bool

    private var isNew: Bool {
        if case .addNew = mode { return true }
        return false
    }
    private var isEnglishLocale: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en") == "en"
    }
    private var shouldShowInstallmentUI: Bool {
        !isEnglishLocale && enableInstallment
    }
    private var isValid:    Bool { nAmount > 0 }
    private var usePointCandidates: [String] {
        // 過去入力を頻度順で候補化する（空文字は除外）
        var counts: [String: Int] = [:]
        for record in pastRecords {
            let key = record.zName.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                continue
            }
            counts[key, default: 0] += 1
        }
        return counts.keys.sorted { a, b in
            let ca = counts[a, default: 0]
            let cb = counts[b, default: 0]
            if ca == cb {
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            return cb < ca
        }
    }
    private var hasChanges: Bool {
        guard let initialDraft else { return false }
        return currentDraft() != initialDraft
    }
    // 済みレコードはコア項目（金額・利用日・決済手段）を固定する
    private var isCoreFieldsLocked: Bool {
        guard case .edit(let record) = mode else { return false }
        if record.e6parts.isEmpty { return false }
        return record.e6parts.allSatisfy { $0.e2invoice?.isPaid ?? false }
    }
    private var shownUsePointCandidates: [String] {
        // フォーカス時に候補をそのまま表示する
        let keyword = zName.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return Array(usePointCandidates.prefix(10))
        }
        let filtered = usePointCandidates.filter { $0.localizedCaseInsensitiveContains(keyword) }
        if filtered.isEmpty {
            return Array(usePointCandidates.prefix(10))
        }
        return Array(filtered.prefix(10))
    }

    private let repeatOptions: [(label: String, value: Int16)] = [
        ("repeat.none", 0), ("repeat.nextMonth", 1),
        ("repeat.2months", 2), ("repeat.12months", 12)
    ]
    private var repeatLabelKey: LocalizedStringKey {
        if let option = repeatOptions.first(where: { $0.value == nRepeat }) {
            return LocalizedStringKey(option.label)
        }
        return LocalizedStringKey("repeat.none")
    }

    var body: some View {
        Form {
            // ── 必須 ──────────────────────────
            Section {
                // 金額
                Button { showAmountPad = true } label: {
                    HStack {
                        Text("record.field.amount")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(nAmount == 0 ? "—" : nAmount.currencyString())
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(nAmount == 0 ? Color(.tertiaryLabel) : COLOR_AMOUNT_POSITIVE)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCoreFieldsLocked)

                // 利用日はセル全体のタップで選択画面を開く
                Button { showDatePicker = true } label: {
                    HStack {
                        Text("record.field.date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppDateFormat.singleLineText(dateUse))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCoreFieldsLocked)

                // 決済手段（必須パネル・保存は未選択でも可）
                Button { showCardPicker = true } label: {
                    HStack {
                        Text("record.field.card")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let card = selectedCard {
                            Text(card.zName).foregroundStyle(.primary)
                        } else {
                            Text("label.noSelection").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCoreFieldsLocked)
            }

            // ── オプション ────────────────────
            Section {
                // 利用点（自由入力 + 頻度候補）
                VStack(alignment: .leading, spacing: 8) {
                    TextField("record.field.usePoint", text: $zName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isUsePointFocused)
                        .onChange(of: zName) { _, newValue in
                            // 利用点は最大100文字までに制限する
                            if 100 < newValue.count {
                                zName = String(newValue.prefix(100))
                            }
                        }

                    if isUsePointFocused && !shownUsePointCandidates.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(shownUsePointCandidates, id: \.self) { candidate in
                                Button {
                                    // 候補タップで確定する
                                    zName = candidate
                                    isUsePointFocused = false
                                } label: {
                                    HStack(spacing: 0) {
                                        Text(candidate)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if candidate != shownUsePointCandidates.last {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // 分類タグ（複数選択）
                Button { showCategoryPicker = true } label: {
                    HStack(alignment: .top, spacing: 6) {
                        // 見出しは固定幅を確保して欠けないようにする
                        Text("record.field.category")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        categoryLabel
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 支払方法
                if shouldShowInstallmentUI {
                    Picker("record.field.payType", selection: $payType) {
                        ForEach(PayType.allCases, id: \.self) { t in
                            Text(LocalizedStringKey(t.localizedKey)).tag(t)
                        }
                    }
                    .foregroundStyle(Color(.label))
                }

                // 繰り返し
                if payType == .lumpSum {
                    Button { showRepeatPicker = true } label: {
                        HStack {
                            Text("record.field.repeat")
                                // 他の見出しと同じ薄さにそろえる
                                .foregroundStyle(Color(.secondaryLabel))
                            Spacer()
                            Text(repeatLabelKey)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // メモ
                TextField("record.field.note", text: $zNote, axis: .vertical)
                    .lineLimit(3...)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(isNew ? "record.edit.title.add" : "record.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew ? hasChanges : true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew {
                    if hasChanges {
                        Button("button.cancel") { dismiss() }
                    }
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("button.save") { save() }
                    .disabled(!isValid)
                    .fontWeight(hasChanges ? .semibold : .regular)
                    .foregroundStyle(hasChanges ? .blue : .secondary)
            }
        }
        .onAppear {
            if !hasInitialized {
                loadFields()
                initialDraft = currentDraft()
                hasInitialized = true
                if isNew {
                    DispatchQueue.main.async { showAmountPad = true }
                }
            }
        }
        .sheet(isPresented: $showAmountPad) {
            NumericKeypadSheet(
                title: "record.field.amount",
                unit: "record.unit.yen",
                placeholder: nAmount,
                maxValue: APP_MAX_AMOUNT
            ) { value in
                nAmount = value.roundedAmount()
                // 金額確定後は決済ラベル入力へ移動する
                DispatchQueue.main.async { isUsePointFocused = true }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                Form {
                    DatePicker("record.field.date",
                               selection: $dateUse,
                               in: APP_MIN_DATE...APP_MAX_DATE,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                .navigationTitle("record.field.date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("button.done") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCardPicker) {
            PickerSheet(
                title: "record.field.card",
                items: cards,
                selected: $selectedCard,
                label: { $0.zName },
                allowNone: true,
                addContent: { AnyView(NavigationStack { CardEditView() }) }
            )
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryMultiPickerSheet(
                title: "record.field.category",
                items: categories.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending },
                selectedCategories: $selectedCategories
            )
        }
        .sheet(isPresented: $showRepeatPicker) {
            NavigationStack {
                List {
                    ForEach(repeatOptions, id: \.value) { option in
                        Button {
                            nRepeat = option.value
                            showRepeatPicker = false
                        } label: {
                            HStack {
                                Text(LocalizedStringKey(option.label))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if nRepeat == option.value {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationTitle("record.field.repeat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("button.cancel") { showRepeatPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if savedBanner {
                SavedBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: savedBanner)
    }

    // MARK: - Category Label

    @ViewBuilder private var categoryLabel: some View {
        if selectedCategories.isEmpty {
            Text("label.noSelection")
                .foregroundStyle(.secondary)
        } else {
            // タグはカプセルを横並びにし、収まらない分は折り返す
            ChipFlowLayout(spacing: 6) {
                ForEach(selectedCategories) { category in
                    Text(category.zName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemFill))
                        .clipShape(Capsule())
                        .foregroundStyle(.primary)
                }
            }
            // セル幅いっぱいを使って折り返し、高さを自然に拡張する
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Load / Save

    private func loadFields() {
        if case .addNew = mode {
            // 新規時は直近利用の決済手段を初期選択する
            selectedCard = latestUsedCard()
            return
        }
        guard case .edit(let r) = mode else { return }
        dateUse            = r.dateUse
        zName              = r.zName.isEmpty ? (r.e4shop?.zName ?? "") : r.zName
        zNote              = r.zNote
        nAmount            = r.nAmount
        payType            = r.payType
        nRepeat            = r.nRepeat
        selectedCard       = r.e1card
        // 新しい多対多を優先、なければ旧フィールドから移行
        if !r.e5categories.isEmpty {
            selectedCategories = r.e5categories
        } else if let cat = r.e5category {
            selectedCategories = [cat]
        }
    }

    private func save() {
        guard nAmount > 0 else { return }
        let usePoint = zName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .addNew:
            let r = E3record(dateUse: dateUse, zName: usePoint, zNote: zNote,
                             nAmount: nAmount, nPayType: payType.rawValue, nRepeat: nRepeat)
            r.e1card = selectedCard; r.e4shop = nil
            r.e5categories = selectedCategories; r.e5category = nil
            context.insert(r)
            RecordService.save(r, context: context)
            switch afterSaveAction {
            case .goBack:
                dismiss()
            case .continuous:
                resetForm()
                initialDraft = currentDraft()
                showBanner()
                DispatchQueue.main.async { showAmountPad = true }
            case .showHistory:
                onSaved?()
            }
        case .edit(let r):
            for part in r.e6parts { context.delete(part) }
            r.e6parts.removeAll()
            r.dateUse = dateUse; r.zName = usePoint; r.zNote = zNote
            r.nAmount = nAmount; r.nPayType = payType.rawValue; r.nRepeat = nRepeat
            r.e1card = selectedCard; r.e4shop = nil
            r.e5categories = selectedCategories; r.e5category = nil
            RecordService.save(r, context: context)
            dismiss()
        }
    }

    private func resetForm() {
        dateUse = Date(); zName = ""; zNote = ""; nAmount = 0
        payType = .lumpSum; nRepeat = 0
        selectedCard = latestUsedCard(); selectedCategories = []
    }

    private func showBanner() {
        savedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { savedBanner = false }
    }

    // MARK: - Draft

    private struct DraftState: Equatable {
        let dateUse: Date; let zName: String; let zNote: String; let nAmount: Decimal
        let payType: PayType; let nRepeat: Int16
        let cardID: String?; let categoryIDs: [String]
    }

    private func currentDraft() -> DraftState {
        DraftState(dateUse: dateUse, zName: zName, zNote: zNote, nAmount: nAmount,
                   payType: payType, nRepeat: nRepeat,
                   cardID: selectedCard?.id,
                   categoryIDs: selectedCategories.map(\.id).sorted())
    }

    // 直近の利用レコードから決済手段を拾う
    private func latestUsedCard() -> E1card? {
        for record in pastRecords {
            if let card = record.e1card {
                return card
            }
        }
        return nil
    }
}

// MARK: - Generic Single-Select Picker Sheet

private struct PickerSheet<T: Identifiable>: View where T.ID: Equatable {
    let title: LocalizedStringKey
    let items: [T]
    @Binding var selected: T?
    let label: (T) -> String
    let allowNone: Bool
    var addContent: (() -> AnyView)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var itemIDsBeforeAdd: [T.ID] = []

    var body: some View {
        NavigationStack {
            List {
                if allowNone {
                    Button {
                        selected = nil; dismiss()
                    } label: {
                        HStack {
                            Text("label.noSelection").foregroundStyle(.secondary)
                            Spacer()
                            if selected == nil { Image(systemName: "checkmark").foregroundStyle(.blue) }
                        }
                        .contentShape(Rectangle())
                    }
                }
                ForEach(items) { item in
                    Button {
                        selected = item; dismiss()
                    } label: {
                        HStack {
                            Text(label(item)).foregroundStyle(.primary)
                            Spacer()
                            if selected?.id == item.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.cancel") { dismiss() }
                }
                if addContent != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            itemIDsBeforeAdd = items.map(\.id)
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: {
                if let newItem = items.first(where: { !itemIDsBeforeAdd.contains($0.id) }) {
                    selected = newItem
                }
            }) {
                addContent?()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Category Multi-Select Picker Sheet

private struct CategoryMultiPickerSheet: View {
    let title: LocalizedStringKey
    let items: [E5category]
    @Binding var selectedCategories: [E5category]

    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var displayOrder: [E5category] = []
    @State private var itemIDsBeforeAdd: [String] = []
    private let maxSelection = 10

    var body: some View {
        NavigationStack {
            List {
                ForEach(displayOrder) { item in
                    Button {
                        toggleItem(item)
                    } label: {
                        HStack {
                            Text(item.zName).foregroundStyle(.primary)
                            Spacer()
                            if selectedCategories.contains(where: { $0.id == item.id }) {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        itemIDsBeforeAdd = items.map(\.id)
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("button.done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: {
                let newItems = items.filter { !itemIDsBeforeAdd.contains($0.id) }
                for item in newItems where !selectedCategories.contains(where: { $0.id == item.id }) {
                    selectedCategories.append(item)
                    displayOrder.append(item)
                }
            }) {
                NavigationStack { CategoryEditView() }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // 選択済みを先頭に、残りはアルファベット順
            let selectedIDs = Set(selectedCategories.map(\.id))
            let selected   = items.filter {  selectedIDs.contains($0.id) }
            let unselected = items.filter { !selectedIDs.contains($0.id) }
            displayOrder = selected + unselected
        }
    }

    private func toggleItem(_ item: E5category) {
        if let idx = selectedCategories.firstIndex(where: { $0.id == item.id }) {
            selectedCategories.remove(at: idx)
        } else {
            // 選択数の上限を超える追加は行わない
            if maxSelection <= selectedCategories.count {
                return
            }
            selectedCategories.append(item)
        }
    }
}

// MARK: - Chip Flow Layout

private struct ChipFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // 横幅提案が未指定の場合でも、画面幅ベースで折り返しを有効化する
        let proposedWidth = proposal.width ?? (UIScreen.main.bounds.width - 140)
        let maxWidth = max(0, proposedWidth)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if maxWidth < x + size.width, x != 0 {
                usedWidth = max(usedWidth, x - spacing)
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        if !subviews.isEmpty {
            usedWidth = max(usedWidth, x - spacing)
            y += lineHeight
        }
        return CGSize(width: min(maxWidth, usedWidth), height: y)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if bounds.maxX < x + size.width, bounds.minX != x {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Saved Banner

private struct SavedBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("alert.saved").font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
    }
}
