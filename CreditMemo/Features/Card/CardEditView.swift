import SwiftUI
import SwiftData

struct CardEditView: View {
    var card: E1card?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \E1card.nRow)   private var allCards: [E1card]
    @Query(sort: \E8bank.nRow)   private var banks: [E8bank]

    @State private var zName       = ""
    @State private var zNote       = ""
    @State private var selectedBank: E8bank?
    @State private var bankSelection: BankSelection = .none
    @State private var previousBankSelection: BankSelection = .none
    @State private var showBankAddSheet = false
    @State private var bankCountBeforeAdd = 0
    @State private var closingDaySelection: Int16 = 27
    @State private var payDay:     Int16 = 27
    @State private var payMonth:   Int16 = 1
    @State private var usesAfterDays = false
    @State private var daysLater: Int16 = 7
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
        closingDaySelection
    }
    private var effectiveDaysLater: Int16 {
        // 0 は「当日」を許可する
        if daysLater < 0 {
            return 0
        }
        return daysLater
    }
    private var hasChanges: Bool {
        guard let base = initialDraft else { return false }
        return currentDraft() != base
    }
    private var billingModeCycleText: LocalizedStringKey {
        isEnglishLocale ? "Closing/Payment Day" : "締日/支払日型"
    }
    private var billingModeAfterDaysText: LocalizedStringKey {
        isEnglishLocale ? "N Days" : "N日後型"
    }
    private var billingModeTitleText: LocalizedStringKey {
        isEnglishLocale ? "Billing Type" : "請求方式"
    }

    var body: some View {
        Form {
            // 先頭はプリセット操作のみ
            if isNew {
                Section {
                    // プリセットを呼び出すボタン
                    Button("card.preset.quote") {
                        showPresetDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // 基本情報
            Section {
                // 決済名はプレースホルダー表示にして左寄せ入力する
                TextField("card.field.name", text: $zName)
                    .autocorrectionDisabled()
                    .focused($focusName)
                    .multilineTextAlignment(.leading)

                AdaptiveValueRow(titleKey: "card.field.bank") {
                    Picker("", selection: $bankSelection) {
                        Text("label.noSelection").tag(BankSelection.none)
                        // 口座追加導線を目立たせる
                        Text("card.bank.addNew").tag(BankSelection.addNew)
                        ForEach(banks) { b in
                            Text(b.zName).tag(BankSelection.existing(b.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

            }

            // 締日〜支払設定を1パネルにまとめる
            Section {
                AdaptiveValueRow(titleKey: billingModeTitleText) {
                    Picker("", selection: $usesAfterDays) {
                        Text(billingModeCycleText).tag(false)
                        Text(billingModeAfterDaysText).tag(true)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                if !usesAfterDays {
                    AdaptiveValueRow(titleKey: "card.field.closingDay") {
                        Picker("", selection: $closingDaySelection) {
                            ForEach(Array(1...28), id: \.self) { d in
                                Text("\(d)").tag(Int16(d))
                            }
                            Text("card.closingDay.end").tag(Int16(29))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    AdaptiveValueRow(titleKey: "card.field.payMonth") {
                        Picker("", selection: $payMonth) {
                            Text("card.payMonth.current").tag(Int16(0))
                            Text("card.payMonth.next").tag(Int16(1))
                            Text("card.payMonth.twoMonths").tag(Int16(2))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    AdaptiveValueRow(titleKey: "card.field.payDay") {
                        Picker("", selection: $payDay) {
                            ForEach(Array(1...28), id: \.self) { d in
                                Text("\(d)").tag(Int16(d))
                            }
                            Text("card.closingDay.end").tag(Int16(29))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                } else {
                    // N日後型は見出しを出さず、値選択のみ表示する
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Picker("", selection: $daysLater) {
                            ForEach(Array(0...120), id: \.self) { day in
                                if day == 0 {
                                    Text(isEnglishLocale ? "0 Days (Use Date)" : "0日後（利用日払）").tag(Int16(day))
                                } else {
                                    Text(isEnglishLocale ? "\(day) Days Later" : "\(day)日後").tag(Int16(day))
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }

            // メモ
            Section {
                // メモは複数行入力できる TextEditor を使う
                ZStack(alignment: .topLeading) {
                    if zNote.isEmpty {
                        Text("card.field.note")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $zNote)
                        .frame(minHeight: 72)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .autocorrectionDisabled()
                }
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
        .onChange(of: usesAfterDays) { _, newValue in
            if newValue == false {
                normalizeCycleFieldsIfNeeded()
            }
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
            return
        }
        zName        = card.zName
        zNote        = card.zNote
        usesAfterDays = card.nClosingDay == 0
        // N日後型は nPayDay をそのまま日数として読む
        daysLater    = usesAfterDays ? card.nPayDay : 7
        // 請求方式ごとの既定値に寄せる
        closingDaySelection = usesAfterDays ? 0 : (0 < card.nClosingDay ? card.nClosingDay : 27)
        payDay       = 0 < card.nPayDay ? card.nPayDay : 27
        payMonth     = card.nPayMonth
        selectedBank = card.e8bank
        bankSelection = selectionFromBank(selectedBank)
        previousBankSelection = bankSelection
    }

    private func save() {
        let name = zName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let closingDay = usesAfterDays ? Int16(0) : effectiveClosingDay
        let savingPayDay: Int16 = usesAfterDays ? effectiveDaysLater : payDay
        let savingPayMonth: Int16 = usesAfterDays ? 0 : payMonth

        if let card {
            card.zName       = name
            card.zNote       = zNote
            card.nClosingDay = closingDay
            card.nPayDay     = savingPayDay
            card.nPayMonth   = savingPayMonth
            // ボーナス月は廃止し、常に未設定(0)で保存する
            card.nBonus1      = 0
            card.nBonus2      = 0
            card.e8bank       = selectedBank
            card.dateUpdate   = Date()
            // 決済手段マスタ変更は請求全体へ影響するため全件再構築する
            RecordService.rebuildBilling(context: context)
        } else {
            // 新規追加は一覧先頭へ出すため、最小rowよりさらに小さい値を採用する
            let row = Int32((allCards.map { Int($0.nRow) }.min() ?? 1) - 1)
            let c = E1card(
                zName: name, zNote: zNote, nRow: row,
                nClosingDay: closingDay, nPayDay: savingPayDay, nPayMonth: savingPayMonth,
                nBonus1: 0, nBonus2: 0,
                dateUpdate: Date()
            )
            c.e8bank = selectedBank
            context.insert(c)
        }
        if context.hasChanges {
            try? context.save()
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
        // プリセットに説明メモがある場合はメモへ反映する
        zNote = preset.note
        // 締日=0 を N日後型として扱う
        usesAfterDays = preset.closingDay == 0
        // N日後型は payDay をそのまま N 日として使う
        daysLater = usesAfterDays ? preset.payDay : 0
        // プリセットは内部値どおりにそのまま反映する
        closingDaySelection = usesAfterDays ? 0 : preset.closingDay
        payDay = preset.payDay
        payMonth = preset.payMonth
    }

    private func normalizeCycleFieldsIfNeeded() {
        // 締日/支払日型へ戻した時だけ、0 のまま残る値を補正する
        if closingDaySelection == 0 {
            closingDaySelection = 27
        }
        if payMonth == 0 {
            payMonth = 1
        }
        if payDay == 0 {
            payDay = 27
        }
    }

    // MARK: - Draft Diff

    /// 変更検知用の編集スナップショット
    private struct DraftState: Equatable {
        let zName: String
        let zNote: String
        let bankID: String?
        let usesAfterDays: Bool
        let daysLater: Int16
        let closingDaySelection: Int16
        let payDay: Int16
        let payMonth: Int16
    }

    private func currentDraft() -> DraftState {
        DraftState(
            zName: zName,
            zNote: zNote,
            bankID: selectedBank?.id,
            usesAfterDays: usesAfterDays,
            daysLater: daysLater,
            closingDaySelection: closingDaySelection,
            payDay: payDay,
            payMonth: payMonth
        )
    }

}

/// 1行優先で表示し、収まらない場合だけ値を2行目右寄せで表示する行コンポーネント
private struct AdaptiveValueRow<ValueView: View>: View {
    let titleKey: LocalizedStringKey
    @ViewBuilder let valueView: () -> ValueView

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titleKey)
                    .lineLimit(1)
                Spacer(minLength: 0)
                valueView()
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(titleKey)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    valueView()
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
