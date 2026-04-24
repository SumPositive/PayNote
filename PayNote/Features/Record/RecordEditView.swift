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

    @Environment(\.modelContext)  private var context
    @Environment(\.dismiss)       private var dismiss
    @Query(sort: \E1card.nRow)    private var cards: [E1card]
    @Query                        private var shops: [E4shop]
    @Query                        private var categories: [E5category]

    @AppStorage(AppStorageKey.enableInstallment) private var enableInstallment = false

    @State private var dateUse:    Date     = Date()
    @State private var zNote:      String   = ""
    @State private var nAmount:    Decimal  = 0
    @State private var payType:    PayType  = .lumpSum
    @State private var nRepeat:    Int16    = 0
    @State private var selectedCard:        E1card?
    @State private var selectedShop:        E4shop?
    @State private var selectedCategories:  [E5category] = []

    @State private var showAmountPad      = false
    @State private var showCardPicker     = false
    @State private var showShopPicker     = false
    @State private var showCategoryPicker = false
    @State private var savedBanner        = false
    @State private var hasInitialized     = false
    @State private var initialDraft: DraftState?

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
    private var hasChanges: Bool {
        guard let initialDraft else { return false }
        return currentDraft() != initialDraft
    }

    private let repeatOptions: [(label: String, value: Int16)] = [
        ("repeat.none", 0), ("repeat.nextMonth", 1),
        ("repeat.2months", 2), ("repeat.12months", 12)
    ]

    var body: some View {
        Form {
            // ── 必須 ──────────────────────────
            Section {
                // 金額
                Button { showAmountPad = true } label: {
                    HStack {
                        Text("record.field.amount")
                            .foregroundStyle(Color(.label))
                        Spacer()
                        Text(nAmount == 0 ? "—" : nAmount.currencyString())
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(nAmount == 0 ? Color(.tertiaryLabel) : COLOR_AMOUNT_POSITIVE)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 利用日
                DatePicker("record.field.date",
                           selection: $dateUse,
                           in: APP_MIN_DATE...APP_MAX_DATE,
                           displayedComponents: .date)
                .foregroundStyle(Color(.label))

                // 決済手段（必須パネル・保存は未選択でも可）
                Button { showCardPicker = true } label: {
                    HStack {
                        Text("record.field.card")
                            .foregroundStyle(Color(.label))
                        Spacer()
                        if let card = selectedCard {
                            Text(card.zName).foregroundStyle(.secondary)
                        } else {
                            Text("label.noSelection").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // ── オプション ────────────────────
            Section {
                // 利用店
                Button { showShopPicker = true } label: {
                    HStack {
                        Text("record.field.shop")
                            .foregroundStyle(Color(.label))
                        Spacer()
                        if let shop = selectedShop {
                            Text(shop.zName).foregroundStyle(.secondary)
                        } else {
                            Text("label.noSelection").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 分類タグ（複数選択）
                Button { showCategoryPicker = true } label: {
                    HStack {
                        Text("record.field.category")
                            .foregroundStyle(Color(.label))
                        Spacer()
                        categoryLabel
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
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
                    Picker("record.field.repeat", selection: $nRepeat) {
                        ForEach(repeatOptions, id: \.value) { opt in
                            Text(LocalizedStringKey(opt.label)).tag(opt.value)
                        }
                    }
                    .foregroundStyle(Color(.label))
                }

                // メモ
                TextField("record.field.note", text: $zNote, axis: .vertical)
                    .lineLimit(3...)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(isNew ? "record.edit.title.add" : "record.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew {
                    Button("button.cancel") { dismiss() }
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
            ) { nAmount = $0.roundedAmount() }
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
        .sheet(isPresented: $showShopPicker) {
            PickerSheet(
                title: "record.field.shop",
                items: shops.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending },
                selected: $selectedShop,
                label: { $0.zName },
                allowNone: true,
                addContent: { AnyView(NavigationStack { ShopEditView(shop: nil) }) }
            )
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryMultiPickerSheet(
                title: "record.field.category",
                items: categories.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending },
                selectedCategories: $selectedCategories
            )
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
            Text("label.noSelection").foregroundStyle(.secondary)
        } else if selectedCategories.count == 1 {
            Text(selectedCategories[0].zName).foregroundStyle(.secondary)
        } else {
            Text(selectedCategories[0].zName + " +\(selectedCategories.count - 1)")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Load / Save

    private func loadFields() {
        guard case .edit(let r) = mode else { return }
        dateUse            = r.dateUse
        zNote              = r.zNote.isEmpty ? r.zName : r.zNote
        nAmount            = r.nAmount
        payType            = r.payType
        nRepeat            = r.nRepeat
        selectedCard       = r.e1card
        selectedShop       = r.e4shop
        // 新しい多対多を優先、なければ旧フィールドから移行
        if !r.e5categories.isEmpty {
            selectedCategories = r.e5categories
        } else if let cat = r.e5category {
            selectedCategories = [cat]
        }
    }

    private func save() {
        guard nAmount > 0 else { return }
        switch mode {
        case .addNew:
            let r = E3record(dateUse: dateUse, zName: "", zNote: zNote,
                             nAmount: nAmount, nPayType: payType.rawValue, nRepeat: nRepeat)
            r.e1card = selectedCard; r.e4shop = selectedShop
            r.e5categories = selectedCategories; r.e5category = nil
            context.insert(r)
            RecordService.save(r, context: context)
            resetForm()
            showBanner()
        case .edit(let r):
            for part in r.e6parts { context.delete(part) }
            r.e6parts.removeAll()
            r.dateUse = dateUse; r.zName = ""; r.zNote = zNote
            r.nAmount = nAmount; r.nPayType = payType.rawValue; r.nRepeat = nRepeat
            r.e1card = selectedCard; r.e4shop = selectedShop
            r.e5categories = selectedCategories; r.e5category = nil
            RecordService.save(r, context: context)
            dismiss()
        }
    }

    private func resetForm() {
        dateUse = Date(); zNote = ""; nAmount = 0
        payType = .lumpSum; nRepeat = 0
        selectedCard = nil; selectedShop = nil; selectedCategories = []
    }

    private func showBanner() {
        savedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { savedBanner = false }
    }

    // MARK: - Draft

    private struct DraftState: Equatable {
        let dateUse: Date; let zNote: String; let nAmount: Decimal
        let payType: PayType; let nRepeat: Int16
        let cardID: String?; let shopID: String?; let categoryIDs: [String]
    }

    private func currentDraft() -> DraftState {
        DraftState(dateUse: dateUse, zNote: zNote, nAmount: nAmount,
                   payType: payType, nRepeat: nRepeat,
                   cardID: selectedCard?.id, shopID: selectedShop?.id,
                   categoryIDs: selectedCategories.map(\.id).sorted())
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
            selectedCategories.append(item)
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
