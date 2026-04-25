import SwiftUI
import SwiftData

struct CardEditView: View {
    var card: E1card?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner
    @Query(sort: \E1card.nRow)   private var allCards: [E1card]
    @Query(sort: \E8bank.nRow)   private var banks: [E8bank]

    @State private var zName       = ""
    @State private var zNote       = ""
    @State private var selectedBank: E8bank?
    @State private var bankSelection: BankSelection = .none
    @State private var previousBankSelection: BankSelection = .none
    @State private var showBankAddSheet = false
    @State private var bankCountBeforeAdd = 0
    @State private var closingDaySelection: Int16? = 20
    @State private var payDay:     Int16 = 27
    @State private var payMonth:   Int16 = 1
    @State private var manageLevel:  ManagementLevel = .precise
    @State private var showPresetDialog = false
    @State private var hasInitialized = false
    @State private var initialDraft: DraftState?
    @FocusState private var focusName: Bool

    private var isNew:   Bool { card == nil }
    private var isValid: Bool { !zName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var presetTemplates: [SeedData.CardPreset] { SeedData.presetsForCurrentLocale() }
    private var isEnglishLocale: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en") == "en"
    }
    private var effectiveClosingDay: Int16 {
        if let closingDaySelection {
            return closingDaySelection
        }
        return payDay
    }
    private var hasChanges: Bool {
        guard let base = initialDraft else { return false }
        return currentDraft() != base
    }

    var body: some View {
        Form {
            // 説明文
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("card.edit.description")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // プリセットを呼び出すボタン
                    if isNew {
                        Button("card.preset.quote") {
                            showPresetDialog = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .listRowSeparator(.hidden)
            }

            // 基本情報
            Section {
                TextField("card.field.name", text: $zName)
                    .autocorrectionDisabled()
                    .focused($focusName)

                LabeledContent("card.field.bank") {
                    Picker("", selection: $bankSelection) {
                        Text("label.noSelection").tag(BankSelection.none)
                        // 口座追加導線を目立たせる
                        Text(newBankOptionText).tag(BankSelection.addNew)
                        ForEach(banks) { b in
                            Text(b.zName).tag(BankSelection.existing(b.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // 管理レベルと補足を同一行にまとめ、間の区切り線を出さない
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("card.field.manageLevel") {
                        Picker("", selection: $manageLevel) {
                            ForEach(ManagementLevel.allCases, id: \.self) { level in
                                Text(LocalizedStringKey(level.labelKey)).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    if userLevel == .beginner {
                        Text(manageLevelHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 締日〜支払設定を1パネルにまとめる
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if !isEnglishLocale {
                        LabeledContent("card.field.closingDay") {
                            Picker("", selection: $closingDaySelection) {
                                ForEach(Array(1...28), id: \.self) { d in
                                    Text("\(d)").tag(Optional(Int16(d)))
                                }
                                Text("card.closingDay.end").tag(Optional(Int16(29)))
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Text("支払（引き落とし）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LabeledContent("月") {
                            Picker("", selection: $payMonth) {
                                Text("card.payMonth.current").tag(Int16(0))
                                Text("card.payMonth.next").tag(Int16(1))
                                Text("card.payMonth.twoMonths").tag(Int16(2))
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    LabeledContent(isEnglishLocale ? "card.field.payDay" : "日") {
                        Picker("", selection: $payDay) {
                            ForEach(Array(1...28), id: \.self) { d in
                                Text("\(d)").tag(Int16(d))
                            }
                            Text("card.closingDay.end").tag(Int16(29))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    if isEnglishLocale {
                        LabeledContent("card.field.closingDay") {
                            Picker("", selection: $closingDaySelection) {
                                Text("label.noSelection").tag(Optional<Int16>.none)
                                ForEach(Array(1...28), id: \.self) { d in
                                    Text("\(d)").tag(Optional(Int16(d)))
                                }
                                Text("card.closingDay.end").tag(Optional(Int16(29)))
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Text("card.field.closingDay.enHelp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 初心者モードのみ補足説明を表示する
                    if userLevel == .beginner {
                        Text(payDayHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // メモ
            Section {
                TextField("card.field.note", text: $zNote, axis: .vertical)
                    .lineLimit(3...)
                    .autocorrectionDisabled()
            }
        }
        .scalableNavigationTitle("card.list.title")
        .navigationBarBackButtonHidden(isNew || hasChanges)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew || hasChanges {
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
        .onChange(of: bankSelection) { _, newValue in
            handleBankSelectionChange(newValue)
        }
        .sheet(isPresented: $showBankAddSheet, onDismiss: applyAddedBankIfNeeded) {
            NavigationStack { BankEditView(bank: nil) }
        }
        .confirmationDialog("card.preset.quote", isPresented: $showPresetDialog) {
            // 候補を選ぶと日付設定と名称を反映する
            ForEach(presetTemplates, id: \.name) { preset in
                Button(preset.name) {
                    applyPreset(preset)
                }
            }
            Button("button.cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func loadFields() {
        guard let card else {
            if isEnglishLocale {
                // en の新規追加は締日を未設定扱いにする
                closingDaySelection = nil
                payMonth = 1
            }
            return
        }
        zName        = card.zName
        zNote        = card.zNote
        if isEnglishLocale && card.nClosingDay == card.nPayDay {
            // en では「未設定(=支払日と同じ)」を表現する
            closingDaySelection = nil
        } else {
            closingDaySelection = 0 < card.nClosingDay ? card.nClosingDay : 20
        }
        payDay       = 0 < card.nPayDay ? card.nPayDay : 27
        payMonth     = card.nPayMonth
        manageLevel  = card.manageLevel
        selectedBank = card.e8bank
        bankSelection = selectionFromBank(selectedBank)
        previousBankSelection = bankSelection
    }

    private func save() {
        let name = zName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let closingDay = effectiveClosingDay
        let savingPayMonth: Int16 = isEnglishLocale ? 1 : payMonth

        if let card {
            card.zName       = name
            card.zNote       = zNote
            card.nClosingDay = closingDay
            card.nPayDay     = payDay
            card.nPayMonth   = savingPayMonth
            // ボーナス月は廃止し、常に未設定(0)で保存する
            card.nBonus1      = 0
            card.nBonus2      = 0
            card.nManageLevel = manageLevel.rawValue
            card.e8bank       = selectedBank
            card.dateUpdate   = Date()
        } else {
            let row = Int32((allCards.map { Int($0.nRow) }.max() ?? -1) + 1)
            let c = E1card(
                zName: name, zNote: zNote, nRow: row,
                nClosingDay: closingDay, nPayDay: payDay, nPayMonth: savingPayMonth,
                nBonus1: 0, nBonus2: 0,
                nManageLevel: manageLevel.rawValue, dateUpdate: Date()
            )
            c.e8bank = selectedBank
            context.insert(c)
        }
        dismiss()
    }

    // MARK: - Bank Picker

    /// 口座選択用の疑似項目（未設定 / 追加 / 既存）
    private enum BankSelection: Hashable {
        case none
        case addNew
        case existing(String)
    }

    private func selectionFromBank(_ bank: E8bank?) -> BankSelection {
        if let id = bank?.id {
            return .existing(id)
        }
        return .none
    }

    private func bankFromSelection(_ selection: BankSelection) -> E8bank? {
        if case let .existing(id) = selection {
            return banks.first { $0.id == id }
        }
        return nil
    }

    private func handleBankSelectionChange(_ newValue: BankSelection) {
        if case .addNew = newValue {
            bankCountBeforeAdd = banks.count
            bankSelection = previousBankSelection
            showBankAddSheet = true
            return
        }
        previousBankSelection = newValue
        selectedBank = bankFromSelection(newValue)
    }

    private func applyAddedBankIfNeeded() {
        // 追加後のみ、最新行の口座を自動選択する
        if bankCountBeforeAdd < banks.count {
            if let added = banks.max(by: { $0.nRow < $1.nRow }) {
                selectedBank = added
                bankSelection = .existing(added.id)
                previousBankSelection = bankSelection
            }
        }
    }

    private func applyPreset(_ preset: SeedData.CardPreset) {
        zName = preset.name
        closingDaySelection = isEnglishLocale ? nil : preset.closingDay
        payDay = preset.payDay
        payMonth = isEnglishLocale ? 1 : preset.payMonth
    }

    // MARK: - Draft Diff

    /// 変更検知用の編集スナップショット
    private struct DraftState: Equatable {
        let zName: String
        let zNote: String
        let bankID: String?
        let closingDaySelection: Int16?
        let payDay: Int16
        let payMonth: Int16
        let manageLevel: ManagementLevel
    }

    private func currentDraft() -> DraftState {
        DraftState(
            zName: zName,
            zNote: zNote,
            bankID: selectedBank?.id,
            closingDaySelection: closingDaySelection,
            payDay: payDay,
            payMonth: payMonth,
            manageLevel: manageLevel
        )
    }

    /// 口座追加メニューの強調ラベル
    private var newBankOptionText: String {
        if isEnglishLocale {
            return "＋ Add New Account"
        }
        return "＋ 新しい口座を追加"
    }

    /// 管理レベルの初心者向け補足
    private var manageLevelHelpText: String {
        if isEnglishLocale {
            return "This only expresses how strictly you self-manage. It does not affect any calculations. Choose the level that fits your style, from strict checking to rough tracking. You can change it anytime."
        }
        return "自己管理の程度を明示するものです。処理に関係も影響もありません。きっちり1円も漏らさずチェックする、おおよそ分かればいい、大金だけ把握できれば十分、くらいの感覚で選択してください。いつでも変更できます"
    }

    /// 締日・支払日の初心者向け補足
    private var payDayHelpText: String {
        if isEnglishLocale {
            return "Set the closing day and payment day defined for this payment method. They are usually listed in your card documents. If unknown, contact your card issuer or set them after checking an actual debit date."
        }
        return "この決済手段で決められている締日と支払日を設定してください。クレジットカードのお届け用紙に記載されているはずですが、わからなければカード会社にお問い合わせください。実際に引き落とされた日を見て設定してもいいです"
    }
}
