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

    // Form state
    @State private var dateUse:    Date     = Date()
    @State private var zName:      String   = ""
    @State private var zNote:      String   = ""
    @State private var nAmount:    Decimal  = 0
    @State private var payType:    PayType  = .lumpSum
    @State private var nRepeat:    Int16    = 0
    @State private var selectedCard:     E1card?
    @State private var selectedShop:     E4shop?
    @State private var selectedCategory: E5category?

    // Sheet controls
    @State private var showAmountPad     = false
    @State private var showCardPicker    = false
    @State private var showShopPicker    = false
    @State private var showCategoryPicker = false

    // Save feedback (addNew mode)
    @State private var savedBanner = false
    @FocusState private var focusName: Bool
    @State private var hasInitialized = false
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

    private var isValid: Bool { nAmount > 0 && selectedCard != nil }
    private var hasChanges: Bool {
        guard let initialDraft else { return false }
        return currentDraft() != initialDraft
    }

    private let repeatOptions: [(label: String, value: Int16)] = [
        ("repeat.none", 0),
        ("repeat.nextMonth", 1),
        ("repeat.2months", 2),
        ("repeat.12months", 12)
    ]

    var body: some View {
        Form {
            // 金額（大きく表示）
            Section {
                Button {
                    showAmountPad = true
                } label: {
                    HStack {
                        Text("record.field.amount").foregroundStyle(.primary)
                        Spacer()
                        Text(nAmount == 0 ? "—" : nAmount.currencyString())
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(nAmount == 0 ? Color(.tertiaryLabel) : COLOR_AMOUNT_POSITIVE)
                    }
                }
            }

            // 基本情報
            Section {
                DatePicker("record.field.date",
                           selection: $dateUse,
                           in: APP_MIN_DATE...APP_MAX_DATE,
                           displayedComponents: .date)

                TextField("record.field.name", text: $zName)
                    .autocorrectionDisabled()
                    .focused($focusName)
            }

            // カード・店・分類
            Section {
                // カード (必須)
                Button {
                    showCardPicker = true
                } label: {
                    HStack {
                        Text("record.field.card").foregroundStyle(.primary)
                        Spacer()
                        Text(selectedCard?.zName ?? "label.noSelection")
                            .foregroundStyle(selectedCard == nil ? .secondary : .primary)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                // 利用店
                Button {
                    showShopPicker = true
                } label: {
                    HStack {
                        Text("record.field.shop").foregroundStyle(.primary)
                        Spacer()
                        Text(selectedShop?.zName ?? "label.optional")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                // 分類
                Button {
                    showCategoryPicker = true
                } label: {
                    HStack {
                        Text("record.field.category").foregroundStyle(.primary)
                        Spacer()
                        Text(selectedCategory?.zName ?? "label.optional")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            // 支払方法（二回払いが有効なとき表示）
            if shouldShowInstallmentUI {
                Section {
                    Picker("record.field.payType", selection: $payType) {
                        ForEach(PayType.allCases, id: \.self) { t in
                            Text(LocalizedStringKey(t.localizedKey)).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text("payType.footer")
                }
            }

            // 繰り返し（一括払いのみ）
            if payType == .lumpSum {
                Section {
                    Picker("record.field.repeat", selection: $nRepeat) {
                        ForEach(repeatOptions, id: \.value) { opt in
                            Text(LocalizedStringKey(opt.label)).tag(opt.value)
                        }
                    }
                } footer: {
                    Text("repeat.footer")
                }
            }

            // メモ
            Section {
                TextField("record.field.note", text: $zNote, axis: .vertical)
                    .lineLimit(3...)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(isNew ? "record.edit.title.add" : "record.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!isNew && hasChanges)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !isNew && hasChanges {
                    Button("button.cancel") { dismiss() }
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
                // 新規追加時は最初の入力欄へフォーカスする
                if isNew {
                    DispatchQueue.main.async { focusName = true }
                }
            }
        }
        // 金額テンキー
        .sheet(isPresented: $showAmountPad) {
            NumericKeypadSheet(
                title: "record.field.amount",
                unit: "record.unit.yen",
                placeholder: nAmount,
                maxValue: APP_MAX_AMOUNT
            ) { value in
                nAmount = value.roundedAmount()
            }
        }
        // カード選択
        .sheet(isPresented: $showCardPicker) {
            PickerSheet(
                title: "record.field.card",
                items: cards,
                selected: $selectedCard,
                label: { $0.zName },
                allowNone: false
            )
        }
        // 店選択
        .sheet(isPresented: $showShopPicker) {
            PickerSheet(
                title: "record.field.shop",
                items: shops.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending },
                selected: $selectedShop,
                label: { $0.zName },
                allowNone: true
            )
        }
        // 分類選択
        .sheet(isPresented: $showCategoryPicker) {
            PickerSheet(
                title: "record.field.category",
                items: categories.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending },
                selected: $selectedCategory,
                label: { $0.zName },
                allowNone: true
            )
        }
        // 保存バナー（addNew）
        .overlay(alignment: .top) {
            if savedBanner {
                SavedBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: savedBanner)
    }

    // MARK: - Load / Save

    private func loadFields() {
        guard case .edit(let r) = mode else {
            // addNew: デフォルト値（カードが1枚だけなら自動選択）
            if cards.count == 1 { selectedCard = cards.first }
            return
        }
        dateUse          = r.dateUse
        zName            = r.zName
        zNote            = r.zNote
        nAmount          = r.nAmount
        payType          = r.payType
        nRepeat          = r.nRepeat
        selectedCard     = r.e1card
        selectedShop     = r.e4shop
        selectedCategory = r.e5category
    }

    private func save() {
        guard let card = selectedCard, nAmount > 0 else { return }

        switch mode {
        case .addNew:
            let r = E3record(
                dateUse: dateUse,
                zName:   zName.trimmingCharacters(in: .whitespaces),
                zNote:   zNote,
                nAmount: nAmount,
                nPayType: payType.rawValue,
                nRepeat:  nRepeat
            )
            r.e1card     = card
            r.e4shop     = selectedShop
            r.e5category = selectedCategory
            context.insert(r)
            RecordService.save(r, context: context)

            // フォームリセット＋バナー表示
            resetForm()
            showBanner()

        case .edit(let r):
            // 既存 E6parts を削除してから再生成
            for part in r.e6parts { context.delete(part) }
            r.e6parts.removeAll()

            r.dateUse    = dateUse
            r.zName      = zName.trimmingCharacters(in: .whitespaces)
            r.zNote      = zNote
            r.nAmount    = nAmount
            r.nPayType   = payType.rawValue
            r.nRepeat    = nRepeat
            r.e1card     = card
            r.e4shop     = selectedShop
            r.e5category = selectedCategory

            RecordService.save(r, context: context)
            dismiss()
        }
    }

    private func resetForm() {
        dateUse          = Date()
        zName            = ""
        zNote            = ""
        nAmount          = 0
        payType          = .lumpSum
        nRepeat          = 0
        selectedShop     = nil
        selectedCategory = nil
        // カードは保持（連続入力しやすい）
    }

    private func showBanner() {
        savedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            savedBanner = false
        }
    }

    // MARK: - Draft Diff

    /// 変更検知用の編集スナップショット
    private struct DraftState: Equatable {
        let dateUse: Date
        let zName: String
        let zNote: String
        let nAmount: Decimal
        let payType: PayType
        let nRepeat: Int16
        let cardID: String?
        let shopID: String?
        let categoryID: String?
    }

    private func currentDraft() -> DraftState {
        DraftState(
            dateUse: dateUse,
            zName: zName,
            zNote: zNote,
            nAmount: nAmount,
            payType: payType,
            nRepeat: nRepeat,
            cardID: selectedCard?.id,
            shopID: selectedShop?.id,
            categoryID: selectedCategory?.id
        )
    }
}

// MARK: - Generic Picker Sheet

private struct PickerSheet<T: Identifiable>: View where T.ID: Equatable {
    let title: LocalizedStringKey
    let items: [T]
    @Binding var selected: T?
    let label: (T) -> String
    let allowNone: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if allowNone {
                    Button {
                        selected = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("label.noSelection").foregroundStyle(.secondary)
                            Spacer()
                            if selected == nil { Image(systemName: "checkmark").foregroundStyle(.blue) }
                        }
                    }
                }
                ForEach(items) { item in
                    Button {
                        selected = item
                        dismiss()
                    } label: {
                        HStack {
                            Text(label(item)).foregroundStyle(.primary)
                            Spacer()
                            if selected?.id == item.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
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
}

// MARK: - Saved Banner

private struct SavedBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("alert.saved")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
    }
}
