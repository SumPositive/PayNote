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
    var onSaved: ((Bool) -> Void)? = nil

    @Environment(\.modelContext)    private var context
    @Environment(\.dismiss)         private var dismiss
    @Environment(AppEditingState.self) private var editingState
    @Query(sort: \E1card.nRow)      private var cards: [E1card]
    @Query(sort: \E8bank.nRow)      private var banks: [E8bank]
    @Query(sort: \E3record.dateUse, order: .reverse) private var pastRecords: [E3record]
    @Query                        private var categories: [E5tag]

    @AppStorage(AppStorageKey.afterSaveAction)   private var afterSaveAction: AfterSaveAction = .goBack
    @AppStorage(AppStorageKey.userLevel)         private var userLevel: UserLevel = .beginner
    @AppStorage(AppStorageKey.fontScale)         private var fontScale: FontScale = .system

    @State private var dateUse:    Date     = Date()
    @State private var zName:      String   = ""
    @State private var zNote:      String   = ""
    @State private var nAmount:    Decimal  = 0
    @State private var payType:    PayType  = .lumpSum
    @State private var nRepeat:    Int16    = 0
    @State private var selectedCard:        E1card?
    @State private var selectedBankForCard: E8bank?
    @State private var selectedCategories:  [E5tag] = []

    @State private var showAmountPad      = false
    @State private var showDatePicker     = false
    @State private var draftDateUse       = Date()
    @State private var showCardPicker     = false
    @State private var showBankPicker     = false
    @State private var showCategoryPicker = false
    @State private var showDeleteAlert    = false
    @State private var savedBanner        = false
    @State private var hasInitialized     = false
    @State private var initialDraft: DraftState?
    @State private var keepBankPickerRowVisible = false
    // 過去データ由来の候補をキャッシュして、毎描画の再計算を避ける
    @State private var cachedUsePointCandidates: [String] = []
    @State private var cachedLatestCard: E1card?
    @State private var cachedCategoryByID: [String: E5tag] = [:]
    @State private var scrollToTopRequest = 0
    @FocusState private var isUsePointFocused: Bool
    private let similarRecordLimit = 10
    private let formTopAnchorID = "record-form-top"

    private var isNew: Bool {
        if case .addNew = mode { return true }
        return false
    }
    private var isValid:    Bool { nAmount != 0 }
    private var usePointCandidates: [String] { cachedUsePointCandidates }
    private var hasChanges: Bool {
        guard let initialDraft else { return false }
        return currentDraft() != initialDraft
    }
    private var shouldShowBankPickerRow: Bool {
        if selectedCard == nil {
            return false
        }
        // 新規・編集とも、いったん表示したら保存/終了まで維持する
        return selectedBankForCard == nil || keepBankPickerRowVisible
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
    private var similarCandidates: [SimilarCandidate] {
        // 過去18ヶ月の履歴を対象に、条件が変わるたび緩くスコアリングする
        let sinceDate = Calendar.current.date(byAdding: .month, value: -18, to: Date()) ?? .distantPast
        var scored: [SimilarCandidate] = []

        for record in pastRecords {
            if record.dateUse < sinceDate {
                continue
            }
            // 編集時は自分自身を候補から除外する
            if case .edit(let editingRecord) = mode, editingRecord.id == record.id {
                continue
            }
            let score = similarityScore(for: record)
            if 0 < score {
                scored.append(SimilarCandidate(record: record, score: score))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return rhs.record.dateUse < lhs.record.dateUse
            }
            return rhs.score < lhs.score
        }
        return Array(scored.prefix(similarRecordLimit))
    }

    private let repeatOptions: [(label: String, value: Int16)] = [
        ("repeat.none", 0), ("repeat.nextMonth", 1),
        ("repeat.2months", 2), ("repeat.12months", 12)
    ]
    private var repeatLabelText: String {
        if let option = repeatOptions.first(where: { $0.value == nRepeat }) {
            return NSLocalizedString(option.label, comment: "")
        }
        return NSLocalizedString("repeat.none", comment: "")
    }
    private var categoryValueText: String {
        if selectedCategories.isEmpty {
            return NSLocalizedString("label.noSelection", comment: "")
        }
        return selectedCategories.map(\.zName).joined(separator: " / ")
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                beginnerSection
                requiredSection
                optionalSection
                similarSection
                deleteSection
            }
            .onChange(of: scrollToTopRequest) { _, _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(formTopAnchorID, anchor: .top)
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    // フォーム外側の軽いタップでラベル入力のフォーカスを外す
                    isUsePointFocused = false
                }
            )
        }
        .navigationTitle(isNew ? "record.edit.title.add" : "record.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew ? hasChanges : true)
        .onChange(of: hasChanges) { _, newValue in
            if newValue { editingState.isEditingInProgress = true }
        }
        .onDisappear {
            editingState.isEditingInProgress = false
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew {
                    if hasChanges {
                        Button("button.cancel") { dismiss() }
                    }
                } else {
                    if hasChanges {
                        // 編集中に変更がある場合は「キャンセル」を表示する
                        Button("button.cancel") { dismiss() }
                    } else {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.down")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                        }
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
                // 初期表示時に候補キャッシュを構築する
                refreshDerivedCaches()
                loadFields()
                initialDraft = currentDraft()
                hasInitialized = true
                if isNew {
                    DispatchQueue.main.async { showAmountPad = true }
                }
            }
        }
        .onChange(of: selectedCard?.id) { _, _ in
            // 決済手段を切り替えたら、その手段に紐づく口座へ追従する
            selectedBankForCard = selectedCard?.e8bank
            // 口座未設定で表示開始した行は、この編集セッション中は保持する
            keepBankPickerRowVisible = selectedCard != nil && selectedBankForCard == nil
        }
        .onChange(of: pastRecords.map(\.id)) { _, _ in
            // レコード集合が変わったときだけ再計算する
            refreshDerivedCaches()
        }
        .sheet(isPresented: $showAmountPad) {
            NumericKeypadSheet(
                title: "record.field.amount",
                placeholder: nAmount,
                maxValue: APP_MAX_AMOUNT
            ) { value in
                nAmount = value.roundedAmount()
                // 金額確定後はフォーカスを外して類似決済を見やすくする
                DispatchQueue.main.async { isUsePointFocused = false }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                Form {
                    // 同じ日を再タップした場合も閉じられるよう、UICalendarView を使う
                    SingleDateCalendarView(
                        selectedDate: $draftDateUse,
                        availableRange: APP_MIN_DATE...APP_MAX_DATE
                    ) { selectedDate in
                        dateUse = selectedDate
                        showDatePicker = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
                }
                .navigationTitle("record.field.date")
                .navigationBarTitleDisplayMode(.inline)
            }
            // カレンダーが欠けない最小寄りの固定高さで表示する
            .presentationDetents([.height(540)])
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
        .sheet(isPresented: $showBankPicker) {
            PickerSheet(
                title: "card.field.bank",
                items: banks,
                selected: $selectedBankForCard,
                label: { $0.zName },
                allowNone: true,
                addContent: { AnyView(NavigationStack { BankEditView(bank: nil) }) }
            )
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryMultiPickerSheet(
                title: "record.field.tag",
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
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                // 削除確認から実処理へ進んだことをログへ残す
                appLog(.debug, "削除確認が確定されました")
                deleteCurrentRecord()
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.message")
        }
        .animation(.spring(duration: 0.3), value: savedBanner)
        // 自動時はシステム設定をそのまま使い、手動時のみ固定サイズを適用する
        .modifier(ConditionalDynamicTypeModifier(fontScale: fontScale))
    }

    // MARK: - Form Sections

    @ViewBuilder private var beginnerSection: some View {
        if userLevel == .beginner {
            Section {
                BeginnerRecordHelpBlock(
                    // 新規と編集で見出しを切り替える
                    titleKey: isNew ? "record.beginner.title" : nil,
                    messageKey: isNew ? "record.beginner.guide" : "record.beginner.guide.edit"
                )
            }
        }
    }

    @ViewBuilder private var requiredSection: some View {
        Section {
            // 金額
            Button { showAmountPad = true } label: {
                twoLineValueRow(
                    titleKey: "record.field.amount",
                    valueText: nAmount == 0 ? "—" : nAmount.currencyString(),
                    valueColor: nAmount == 0 ? Color(.tertiaryLabel) : (nAmount < 0 ? .red : COLOR_AMOUNT_POSITIVE),
                    valueFont: .title2.bold().monospacedDigit(),
                    showsChevron: false
                )
            }
            .id(formTopAnchorID)
            .buttonStyle(.plain)
            .disabled(isCoreFieldsLocked)

            // 利用日はセル全体のタップで選択画面を開く
            Button {
                // シート表示前に現在値を同期する
                draftDateUse = dateUse
                showDatePicker = true
            } label: {
                twoLineValueRow(
                    titleKey: "record.field.date",
                    valueText: AppDateFormat.singleLineText(dateUse),
                    // 選択値はアクセントカラーで見せる
                    valueColor: .accentColor
                )
            }
            .buttonStyle(.plain)
            .disabled(isCoreFieldsLocked)

            // 決済手段（必須パネル・保存は未選択でも可）
            Button { showCardPicker = true } label: {
                twoLineValueRow(
                    titleKey: "record.field.card",
                    valueText: selectedCard?.zName ?? NSLocalizedString("label.noSelection", comment: ""),
                    // 未選択も含めて選択値はアクセントカラーで見せる
                    valueColor: .accentColor
                )
            }
            .buttonStyle(.plain)
            .disabled(isCoreFieldsLocked)

            if shouldShowBankPickerRow {
                // 口座未設定なら、この画面上で口座を選択できるようにする
                Button { showBankPicker = true } label: {
                    twoLineValueRow(
                        titleKey: "card.field.bank",
                        valueText: selectedBankForCard?.zName ?? NSLocalizedString("label.noSelection", comment: ""),
                        // 未選択も含めて口座値はアクセントカラーで見せる
                        valueColor: .accentColor
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCoreFieldsLocked)
            }
        }
    }

    @ViewBuilder private var optionalSection: some View {
        Section {
            // 利用点（自由入力 + 頻度候補）
            VStack(alignment: .leading, spacing: 8) {
                // ラベルは1行入力にし、return でフォーカスを外せるようにする
                TextField("record.field.usePoint", text: $zName)
                    .focused($isUsePointFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        isUsePointFocused = false
                    }
                    .onChange(of: zName) { _, newValue in
                        // ラベルは最大100文字までに制限する
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

            if userLevel != .beginner {
                // 分類タグ（複数選択）
                VStack(alignment: .leading, spacing: 6) {
                    Button { showCategoryPicker = true } label: {
                        ViewThatFits(in: .horizontal) {
                            // 1行版: タイトルと値が収まる場合
                            HStack(spacing: 8) {
                                Text("record.field.tag")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 8)
                                Text(categoryValueText)
                                    // 未選択も含めてタグ値はアクセントカラーで見せる
                                    .foregroundColor(.accentColor)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .fixedSize(horizontal: true, vertical: false)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }

                            // 2行版: 値は全文を右寄せで表示する
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 0) {
                                    Text("record.field.tag")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 8)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    Spacer(minLength: 8)
                                    Text(categoryValueText)
                                        // 未選択も含めてタグ値はアクセントカラーで見せる
                                        .foregroundColor(.accentColor)
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 2)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // 繰り返し
            if payType == .lumpSum && userLevel != .beginner {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("record.field.repeat")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        // 繰り返しは同じ行のメニューピッカーで選択する
                        Picker("record.field.repeat", selection: $nRepeat) {
                            ForEach(repeatOptions, id: \.value) { option in
                                if option.value == 0 {
                                    Text(LocalizedStringKey(option.label))
                                        .tag(option.value)
                                } else {
                                    // 繰り返しありの選択肢だけアイコンを付ける
                                    Label(
                                        title: { Text(LocalizedStringKey(option.label)) },
                                        icon: { Image(systemName: "repeat") }
                                    )
                                    .tag(option.value)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.accentColor)
                    }
                }
            }

            // メモ
            ZStack(alignment: .topLeading) {
                // 入力前はプレースホルダーだけ表示する
                if zNote.isEmpty {
                    Text("record.field.note")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                // メモは改行を許可し、全文を表示する
                TextEditor(text: $zNote)
                    .frame(height: editorHeight(for: zNote, minHeight: 40, maxHeight: 180))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .autocorrectionDisabled()
            }
        } header: {
            privacyHeader
        }
    }

    /// オプション入力欄の上に注意文を1つだけ出す
    @ViewBuilder private var privacyHeader: some View {
        if userLevel == .beginner {
            VStack(alignment: .leading, spacing: 2) {
                Text("record.privacy.warning")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textCase(nil)
        }
    }

    @ViewBuilder private var similarSection: some View {
        // ── 類似決済（新規入力時のみ） ─────────────────────
        if isNew {
            Section(similarSectionHeaderText) {
                if nAmount == 0 {
                    Text(similarGuideText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if similarCandidates.isEmpty {
                    Text(similarEmptyText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(similarCandidates, id: \.record.id) { candidate in
                        Button {
                            applySimilarRecord(candidate.record)
                        } label: {
                            SimilarRecordRow(record: candidate.record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var deleteSection: some View {
        if !isNew {
            Section {
                Button {
                    appLog(.debug, "削除ボタンがタップされました")
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("record.delete.action")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Load / Save

    private func loadFields() {
        if case .addNew = mode {
            // 新規時の決済手段は未選択を初期値にする
            selectedCard = nil
            selectedBankForCard = nil
            keepBankPickerRowVisible = false
            // 新規作成は一括払いのみを許可する
            payType = .lumpSum
            draftDateUse = dateUse
            return
        }
        guard case .edit(let r) = mode else { return }
        dateUse            = r.dateUse
        draftDateUse       = r.dateUse
        zName              = r.zName
        zNote              = r.zNote
        nAmount            = r.nAmount
        payType            = r.payType
        nRepeat            = r.nRepeat
        selectedCard       = r.e1card
        selectedBankForCard = r.e1card?.e8bank
        keepBankPickerRowVisible = selectedCard != nil && selectedBankForCard == nil
        selectedCategories = r.e5tags
    }

    private func save() {
        guard nAmount != 0 else { return }
        let usePoint = zName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousBankID = selectedCard?.e8bank?.id
        let bankChanged = initialDraft?.bankID != selectedBankForCard?.id
        switch mode {
        case .addNew:
            // 保存直前にだけマスタへ口座変更を反映する
            selectedCard?.e8bank = selectedBankForCard
            let r = E3record(dateUse: dateUse, zName: usePoint, zNote: zNote,
                             nAmount: nAmount, nPayType: PayType.lumpSum.rawValue, nRepeat: nRepeat)
            r.e1card = selectedCard
            r.e5tags = selectedCategories
            context.insert(r)
            do {
                try RecordService.save(r, context: context)
            } catch {
                appLog(.error, "新規保存に失敗しました: \(error)")
                // context に乗った未保存の変更（insert・請求再構築・口座変更）を破棄する
                context.rollback()
                return
            }
            applyCardBankChangeIfNeeded(savedRecord: r, previousBankID: previousBankID)
            switch afterSaveAction {
            case .goBack:
                dismiss()
            case .continuous:
                resetForm(keepDateAndCard: false)
                initialDraft = currentDraft()
                showBanner()
                DispatchQueue.main.async { showAmountPad = true }
            case .sameDayCard:
                resetForm(keepDateAndCard: true)
                initialDraft = currentDraft()
                showBanner()
                DispatchQueue.main.async { showAmountPad = true }
            case .showHistory:
                onSaved?(bankChanged)
            }
        case .edit(let r):
            // 保存直前にだけマスタへ口座変更を反映する
            selectedCard?.e8bank = selectedBankForCard
            r.dateUse = dateUse; r.zName = usePoint; r.zNote = zNote
            r.nAmount = nAmount; r.nPayType = payType.rawValue; r.nRepeat = nRepeat
            r.e1card = selectedCard
            r.e5tags = selectedCategories
            do {
                try RecordService.save(r, context: context)
            } catch {
                appLog(.error, "編集保存に失敗しました: \(error)")
                // context に乗った未保存の変更（フィールド更新・請求再構築・口座変更）を破棄する
                context.rollback()
                return
            }
            applyCardBankChangeIfNeeded(savedRecord: r, previousBankID: previousBankID)
            onSaved?(bankChanged)
            dismiss()
        }
    }

    private func deleteCurrentRecord() {
        guard case .edit(let record) = mode else { return }
        appLog(.debug, "削除処理を開始します id=\(record.id)")
        // 削除失敗を握りつぶさず、成功時だけ画面遷移を進める
        do {
            try RecordService.delete(record, context: context)
            appLog(.info, "削除処理が完了しました id=\(record.id)")
        } catch {
            appLog(.error, "削除処理に失敗しました id=\(record.id) error=\(error)")
            return
        }
        onSaved?(false)
        dismiss()
    }

    private func applyCardBankChangeIfNeeded(savedRecord: E3record, previousBankID: String?) {
        guard let card = selectedCard else { return }
        let currentBankID = card.e8bank?.id
        let selectedBankID = selectedBankForCard?.id
        guard previousBankID != currentBankID || currentBankID != selectedBankID else { return }

        // 決済手段マスタの口座変更は同カード配下の請求全体へ影響する
        for sibling in card.e3records where sibling.id != savedRecord.id {
            RecordService.rebuildBilling(for: sibling, context: context)
        }
        RecordService.cleanupOrphanBilling(context: context)
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                appLog(.error, "口座変更後の再保存に失敗しました: \(error)")
            }
        }
    }

    private func resetForm(keepDateAndCard: Bool) {
        zName = ""
        zNote = ""
        nAmount = 0
        payType = .lumpSum
        nRepeat = 0
        selectedCategories = []
        if keepDateAndCard {
            // 同じ日と決済手段だけ残し、残りは空に戻す
            keepBankPickerRowVisible = selectedCard != nil && selectedBankForCard == nil
            return
        }
        dateUse = Date()
        // 通常の連続入力は決済手段も未選択へ戻す
        selectedCard = nil
        selectedBankForCard = nil
        keepBankPickerRowVisible = false
    }

    private func showBanner() {
        savedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { savedBanner = false }
    }

    // MARK: - Draft

    private struct DraftState: Equatable {
        let dateUse: Date; let zName: String; let zNote: String; let nAmount: Decimal
        let payType: PayType; let nRepeat: Int16
        let cardID: String?; let bankID: String?; let categoryIDs: [String]
    }

    private func currentDraft() -> DraftState {
        DraftState(dateUse: dateUse, zName: zName, zNote: zNote, nAmount: nAmount,
                   payType: payType, nRepeat: nRepeat,
                   cardID: selectedCard?.id,
                   bankID: selectedBankForCard?.id,
                   categoryIDs: selectedCategories.map(\.id).sorted())
    }

    // 画面表示で使う派生データをまとめて再計算する
    private func refreshDerivedCaches() {
        // 過去入力を頻度順で候補化する（空文字は除外）
        var counts: [String: Int] = [:]
        for record in pastRecords {
            let key = record.zName.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                continue
            }
            counts[key, default: 0] += 1
        }
        cachedUsePointCandidates = counts.keys.sorted { a, b in
            let ca = counts[a, default: 0]
            let cb = counts[b, default: 0]
            if ca == cb {
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            return cb < ca
        }

        // 直近の利用レコードから決済手段を拾って保持する
        cachedLatestCard = pastRecords.first(where: { $0.e1card != nil })?.e1card
        // 候補適用時にIDから即座に引けるようにカテゴリ辞書を保持する
        cachedCategoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    /// 見出しと値を、収まる場合は1行、収まらない場合は2行で表示する共通セル
    private func twoLineValueRow(
        titleKey: LocalizedStringKey,
        valueText: String,
        valueColor: Color = .primary,
        valueFont: Font = .body,
        showsChevron: Bool = true
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            // 1行版: 収まる場合はこちらを採用する
            HStack(spacing: 8) {
                Text(titleKey)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(valueFont)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            // 2行版: 1行に収まらない場合のみこちらを採用する
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(titleKey)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                }

                HStack(spacing: 6) {
                    Spacer(minLength: 8)
                    Text(valueText)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// 入力文字量に応じたエディタ高さを返す
    private func editorHeight(
        for text: String,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        // 改行数と文字数から概算行数を求めて高さを決める
        let explicitLines = max(1, text.components(separatedBy: "\n").count)
        let wrappedLines = max(1, text.count / 18 + 1)
        let lineCount = max(explicitLines, wrappedLines)
        let estimated = (CGFloat(lineCount) * 22 + 14) * fontScale.uiScale
        return min(maxHeight * fontScale.uiScale, max(minHeight * fontScale.uiScale, estimated))
    }

    // MARK: - Similar Records

    /// 類似候補セクション見出し
    private var similarSectionHeaderText: LocalizedStringKey {
        "record.similar.section.title"
    }

    /// 金額未入力時のガイド文
    private var similarGuideText: LocalizedStringKey {
        "record.similar.guide"
    }

    /// 候補が見つからない場合の文言
    private var similarEmptyText: LocalizedStringKey {
        "record.similar.empty"
    }

    /// 入力条件に対する類似スコアを計算する
    private func similarityScore(for record: E3record) -> Int {
        var score = 0

        // 金額: 完全一致を最優先、差分が大きいほど減点する（符号が異なる候補はスコアなし）
        if nAmount != 0 && (nAmount < 0) == (record.nAmount < 0) {
            if record.nAmount == nAmount {
                score += 80
            } else {
                let ratio = amountDiffRatio(input: nAmount, candidate: record.nAmount)
                if ratio <= 0.05 {
                    score += 55
                } else if ratio <= 0.15 {
                    score += 40
                } else if ratio <= 0.30 {
                    score += 26
                } else if ratio <= 0.50 {
                    score += 14
                } else if ratio <= 1.00 {
                    score += 4
                }
            }
        }

        // 決済手段: 一致を強く優遇する
        if let selectedCardID = selectedCard?.id {
            if record.e1card?.id == selectedCardID {
                score += 34
            } else {
                score += 2
            }
        } else if record.e1card != nil {
            score += 16
        }

        // 決済ラベル: 前方一致・部分一致を優遇する
        let inputLabel = zName.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordLabel = record.zName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inputLabel.isEmpty && !recordLabel.isEmpty {
            if recordLabel == inputLabel {
                score += 30
            } else if recordLabel.localizedCaseInsensitiveContains(inputLabel) {
                score += 18
            }
        } else if !recordLabel.isEmpty {
            score += 16
        }

        // 候補品質: 決済手段/決済ラベルが埋まっている候補を優先する
        if record.e1card != nil {
            score += 10
        }
        if !recordLabel.isEmpty {
            score += 10
        }

        // 曜日一致を軽く優遇する
        if Calendar.current.component(.weekday, from: record.dateUse) ==
            Calendar.current.component(.weekday, from: dateUse) {
            score += 12
        }

        // 分類タグ重複を軽く優遇する
        let selectedCategoryIDs = Set(selectedCategories.map(\.id))
        if !selectedCategoryIDs.isEmpty {
            let overlapCount = record.e5tags.filter { selectedCategoryIDs.contains($0.id) }.count
            if 0 < overlapCount {
                score += min(overlapCount * 6, 18)
            }
        }

        // 新しい記録を少し優遇する（0〜12点）
        let dayDistance = abs(Calendar.current.dateComponents([.day], from: record.dateUse, to: Date()).day ?? 0)
        if dayDistance <= 30 {
            score += 12
        } else if dayDistance <= 90 {
            score += 8
        } else if dayDistance <= 180 {
            score += 4
        }

        return score
    }

    /// 金額差分の比率（0〜∞）を返す
    private func amountDiffRatio(input: Decimal, candidate: Decimal) -> Double {
        let inputValue = max(1.0, NSDecimalNumber(decimal: input).doubleValue)
        let candidateValue = NSDecimalNumber(decimal: candidate).doubleValue
        let diff = abs(inputValue - candidateValue)
        return diff / inputValue
    }

    /// 類似候補を現在のフォームへ反映する
    private func applySimilarRecord(_ record: E3record) {
        // 金額と日付は常に維持し、未入力の項目だけ候補から補う
        if zName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            zName = record.zName
        }
        if zNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            zNote = record.zNote
        }
        if selectedCard == nil {
            selectedCard = record.e1card
        }
        if nRepeat == 0 {
            nRepeat = record.nRepeat
        }

        if selectedCategories.isEmpty {
            // 参照切れを避けるため、現在コンテキストのカテゴリへ張り替える
            selectedCategories = record.e5tags.compactMap { cachedCategoryByID[$0.id] }
        }

        isUsePointFocused = false
        // 候補反映後はフォーム先頭へ戻す
        scrollToTopRequest += 1
    }
}

// MARK: - Calendar View

/// 同日再タップも拾える単一日付カレンダー
private struct SingleDateCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let availableRange: ClosedRange<Date>
    let onSelect: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.locale = Locale.current
        view.availableDateRange = DateInterval(start: availableRange.lowerBound, end: availableRange.upperBound)
        view.fontDesign = .default

        let selection = UICalendarSelectionMultiDate(delegate: context.coordinator)
        view.selectionBehavior = selection

        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        selection.setSelectedDates([components], animated: false)
        view.setVisibleDateComponents(components, animated: false)
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        if context.coordinator.currentComponents != components {
            context.coordinator.currentComponents = components
            if let selection = uiView.selectionBehavior as? UICalendarSelectionMultiDate {
                selection.setSelectedDates([components], animated: false)
            }
            uiView.setVisibleDateComponents(components, animated: false)
        }
    }

    final class Coordinator: NSObject, UICalendarSelectionMultiDateDelegate {
        var parent: SingleDateCalendarView
        var currentComponents: DateComponents

        init(_ parent: SingleDateCalendarView) {
            self.parent = parent
            self.currentComponents = Calendar.current.dateComponents([.year, .month, .day], from: parent.selectedDate)
        }

        func multiDateSelection(
            _ selection: UICalendarSelectionMultiDate,
            canSelectDate dateComponents: DateComponents
        ) -> Bool {
            true
        }

        func multiDateSelection(
            _ selection: UICalendarSelectionMultiDate,
            canDeselectDate dateComponents: DateComponents
        ) -> Bool {
            true
        }

        func multiDateSelection(
            _ selection: UICalendarSelectionMultiDate,
            didSelectDate dateComponents: DateComponents
        ) {
            guard let date = Calendar.current.date(from: dateComponents) else {
                return
            }
            let normalizedDate = Calendar.current.startOfDay(for: date)
            let components = Calendar.current.dateComponents([.year, .month, .day], from: normalizedDate)
            currentComponents = components
            // 常に1件だけ選択状態を維持する
            selection.setSelectedDates([components], animated: false)
            parent.selectedDate = normalizedDate
            parent.onSelect(normalizedDate)
        }

        func multiDateSelection(
            _ selection: UICalendarSelectionMultiDate,
            didDeselectDate dateComponents: DateComponents
        ) {
            guard let date = Calendar.current.date(from: dateComponents) else {
                return
            }
            let normalizedDate = Calendar.current.startOfDay(for: date)
            let components = Calendar.current.dateComponents([.year, .month, .day], from: normalizedDate)
            currentComponents = components
            // 同日タップでも選択状態は維持しつつ閉じる
            selection.setSelectedDates([components], animated: false)
            parent.selectedDate = normalizedDate
            parent.onSelect(normalizedDate)
        }
    }
}

/// 文字サイズの自動/手動適用を切り替える共通モディファイア
private struct ConditionalDynamicTypeModifier: ViewModifier {
    let fontScale: FontScale

    func body(content: Content) -> some View {
        if fontScale.followsSystem {
            content
        } else {
            content.dynamicTypeSize(fontScale.dynamicTypeSize)
        }
    }
}

private struct BeginnerRecordHelpBlock: View {
    let titleKey: LocalizedStringKey?
    let messageKey: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 見出しがある場合だけ表示する
            if let titleKey {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
            }
            Text(messageKey)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Similar Record Row

private struct SimilarRecordRow: View {
    let record: E3record

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(AppDateFormat.singleLineText(record.dateUse))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(record.zName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : record.zName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(record.nAmount.currencyString())
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(record.nAmount < 0 ? Color.red : Color.primary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 8) {
                Text(record.e1card?.zName ?? NSLocalizedString("label.noSelection", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !record.e5tags.isEmpty {
                    Text(record.e5tags.map(\.zName).joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct SimilarCandidate {
    let record: E3record
    let score: Int
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
    @Binding var selectedCategories: [E5tag]

    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [E5tag]
    @State private var showAdd = false
    @State private var displayOrder: [E5tag] = []
    @State private var itemIDsBeforeAdd: [String] = []
    private let maxSelection = 10

    private var items: [E5tag] {
        allCategories.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending }
    }

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
                }
                // 追加直後は新規タグを最上段へ寄せ、同時に選択状態を反映する
                rebuildDisplayOrder(prioritizedIDs: newItems.map(\.id))
            }) {
                NavigationStack { TagEditView() }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            rebuildDisplayOrder()
        }
        .onChange(of: items.map(\.id)) { _, _ in
            // 追加後や一覧更新後も、選択状態に合わせて表示順を組み直す
            rebuildDisplayOrder()
        }
    }

    private func toggleItem(_ item: E5tag) {
        if let idx = selectedCategories.firstIndex(where: { $0.id == item.id }) {
            selectedCategories.remove(at: idx)
        } else {
            // 選択数の上限を超える追加は行わない
            if maxSelection <= selectedCategories.count {
                return
            }
            selectedCategories.append(item)
        }
        rebuildDisplayOrder()
    }

    private func rebuildDisplayOrder(prioritizedIDs: [String] = []) {
        let prioritizedIDSet = Set(prioritizedIDs)
        let selectedIDs = Set(selectedCategories.map(\.id))
        let prioritized = items.filter { prioritizedIDSet.contains($0.id) }
        let selected = items.filter { !prioritizedIDSet.contains($0.id) && selectedIDs.contains($0.id) }
        let unselected = items.filter { !prioritizedIDSet.contains($0.id) && !selectedIDs.contains($0.id) }
        // 新規追加分を最上段、その次に選択済み、その後に未選択を並べる
        displayOrder = prioritized + selected + unselected
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
