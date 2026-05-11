import SwiftUI
import SwiftData

struct TagEditView: View {
    var tag: E5tag?

    @Environment(\.modelContext)    private var context
    @Environment(\.dismiss)         private var dismiss
    @Environment(AppEditingState.self) private var editingState
    @Query private var allTags: [E5tag]
    @Query(sort: \E3record.dateUse, order: .reverse) private var records: [E3record]
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .system

    @State private var zName = ""
    @State private var zNote = ""
    @FocusState private var focusName: Bool
    @State private var hasInitialized = false
    @State private var initialDraft: DraftState?
    @State private var editRecord: E3record?
    // 関連明細の表示用キャッシュ（毎描画での全件走査を避ける）
    @State private var linkedRecordsCache: [E3record] = []

    private var isNew:   Bool { tag == nil }
    private var trimmedName: String {
        zName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasDuplicateName: Bool {
        let normalizedInput = trimmedName.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        if normalizedInput.isEmpty {
            return false
        }
        return allTags.contains { item in
            if item.id == tag?.id {
                return false
            }
            let normalizedExisting = item.zName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            return normalizedExisting == normalizedInput
        }
    }
    private var isValid: Bool { !trimmedName.isEmpty && !hasDuplicateName }
    private var hasChanges: Bool {
        guard let initialDraft else { return false }
        return currentDraft() != initialDraft
    }
    private var linkedRecords: [E3record] { linkedRecordsCache }

    var body: some View {
        Form {
            Section {
                TextField("tag.field.name", text: $zName)
                    .autocorrectionDisabled()
                    .focused($focusName)
                    .trimmingTrailingNewlines($zName)
                if hasDuplicateName {
                    Text("tag.field.name.duplicate")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                // メモは複数行入力にし、内容が欠けない高さへ広げる
                ZStack(alignment: .topLeading) {
                    if zNote.isEmpty {
                        Text("label.note")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $zNote)
                        .frame(height: editorHeight(for: zNote, minHeight: 40, maxHeight: 320))
                        .scrollDisabled(true)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .autocorrectionDisabled()
                        .trimmingTrailingNewlines($zNote)
                }
            }
            if !isNew {
                Section("record.list.title") {
                    if linkedRecords.isEmpty {
                        Text("label.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedRecords) { record in
                            Button {
                                // 明細セルタップで明細編集シートを開く
                                editRecord = record
                            } label: {
                                RecordSummaryRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? "tag.edit.title.add" : "tag.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew || hasChanges)
        .onChange(of: hasChanges) { _, newValue in
            if newValue { editingState.isEditingInProgress = true }
        }
        .onDisappear {
            editingState.isEditingInProgress = false
        }
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
                refreshLinkedRecordsCache()
                initialDraft = currentDraft()
                hasInitialized = true
                // 新規追加時は最初の入力欄へフォーカスする
                if isNew {
                    DispatchQueue.main.async { focusName = true }
                }
            }
        }
        .onChange(of: records.map(\.id)) { _, _ in
            // 関連レコードが変わったときだけ再計算する
            refreshLinkedRecordsCache()
        }
        .sheet(item: $editRecord) { record in
            NavigationStack {
                RecordEditView(mode: .edit(record))
            }
        }
    }

    private func loadFields() {
        guard let tag else { return }
        zName = tag.zName
        zNote = tag.zNote
    }

    private func save() {
        let name = trimmedName
        guard !name.isEmpty && !hasDuplicateName else { return }
        if let tag {
            tag.zName    = name
            tag.zNote    = zNote
            tag.sortName = name
        } else {
            // 新規追加は「最近順」で先頭表示されるよう作成日時を入れる
            let t = E5tag(zName: name, zNote: zNote, sortDate: Date(), sortName: name)
            context.insert(t)
        }
        // 新規追加直後に一覧側へ確実に反映させる
        try? context.save()
        dismiss()
    }

    // MARK: - Draft Diff

    /// 変更検知用の編集スナップショット
    private struct DraftState: Equatable {
        let zName: String
        let zNote: String
    }

    private func currentDraft() -> DraftState {
        DraftState(
            zName: zName,
            zNote: zNote
        )
    }

    private func refreshLinkedRecordsCache() {
        guard let tag else {
            linkedRecordsCache = []
            return
        }
        linkedRecordsCache = records.filter { record in
            record.e5tags.contains(where: { $0.id == tag.id })
        }
    }

    /// メモ量に応じて高さを広げ、内容が欠けないようにする
    private func editorHeight(
        for text: String,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        let explicitLines = max(1, text.components(separatedBy: "\n").count)
        let wrappedLines = max(1, text.count / 18 + 1)
        let lineCount = max(explicitLines, wrappedLines)
        let estimated = (CGFloat(lineCount) * 24 + 24) * fontScale.uiScale
        return min(maxHeight * fontScale.uiScale, max(minHeight * fontScale.uiScale, estimated))
    }
}
