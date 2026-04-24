import SwiftUI
import SwiftData

struct CategoryEditView: View {
    var category: E5category?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @State private var zName = ""
    @State private var zNote = ""
    @FocusState private var focusName: Bool

    private var isNew:   Bool { category == nil }
    private var isValid: Bool { !zName.trimmingCharacters(in: .whitespaces).isEmpty }

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
        }
        .navigationTitle(isNew ? "category.edit.title.add" : "category.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew { Button("button.cancel") { dismiss() } }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("button.save") { save() }.disabled(!isValid)
            }
        }
        .onAppear {
            loadFields()
            // 新規追加時は最初の入力欄へフォーカスする
            if isNew {
                DispatchQueue.main.async { focusName = true }
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
}
