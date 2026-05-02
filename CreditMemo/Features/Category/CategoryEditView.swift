import SwiftUI
import SwiftData

struct CategoryEditView: View {
    var category: E5category?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query private var categories: [E5category]
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

    private var isNew:   Bool { category == nil }
    private var trimmedName: String {
        zName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasDuplicateName: Bool {
        let normalizedInput = trimmedName.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        if normalizedInput.isEmpty {
            return false
        }
        return categories.contains { item in
            if item.id == category?.id {
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
                TextField("category.field.name", text: $zName)
                    .autocorrectionDisabled()
                    .focused($focusName)
                if hasDuplicateName {
                    Text("category.field.name.duplicate")
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
                        .frame(height: editorHeight(for: zNote, minHeight: 40, maxHeight: 180))
                        .scrollDisabled(true)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .autocorrectionDisabled()
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
        .navigationTitle(isNew ? "category.edit.title.add" : "category.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
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
        guard let category else { return }
        zName = category.zName
        zNote = category.zNote
    }

    private func save() {
        let name = trimmedName
        guard !name.isEmpty && !hasDuplicateName else { return }
        if let category {
            category.zName    = name
            category.zNote    = zNote
            category.sortName = name
        } else {
            // 新規追加は「最近順」で先頭表示されるよう作成日時を入れる
            let c = E5category(zName: name, zNote: zNote, sortDate: Date(), sortName: name)
            context.insert(c)
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
        guard let category else {
            linkedRecordsCache = []
            return
        }
        linkedRecordsCache = records.filter { record in
            // 新しい複数タグを優先し、旧単体タグも対象に含める
            if record.e5categories.contains(where: { $0.id == category.id }) {
                return true
            }
            return record.e5category?.id == category.id
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
