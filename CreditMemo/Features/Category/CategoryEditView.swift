import SwiftUI
import SwiftData

struct CategoryEditView: View {
    var category: E5category?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \E3record.dateUse, order: .reverse) private var records: [E3record]

    @State private var zName = ""
    @State private var zNote = ""
    @FocusState private var focusName: Bool
    @State private var hasInitialized = false
    @State private var initialDraft: DraftState?
    @State private var editRecord: E3record?
    // 関連明細の表示用キャッシュ（毎描画での全件走査を避ける）
    @State private var linkedRecordsCache: [E3record] = []

    private var isNew:   Bool { category == nil }
    private var isValid: Bool { !zName.trimmingCharacters(in: .whitespaces).isEmpty }
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
            }
            Section {
                TextField("label.note", text: $zNote)
                    .autocorrectionDisabled()
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
        let name = zName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let category {
            category.zName    = name
            category.zNote    = zNote
            category.sortName = name
        } else {
            let c = E5category(zName: name, zNote: zNote, sortName: name)
            context.insert(c)
        }
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
}
