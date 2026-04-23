import SwiftUI
import SwiftData

struct ShopEditView: View {
    var shop: E4shop?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @State private var zName = ""
    @State private var zNote = ""

    private var isNew:   Bool { shop == nil }
    private var isValid: Bool { !zName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("shop.field.name", text: $zName)
                    .autocorrectionDisabled()
            }
            Section {
                TextField("label.note", text: $zNote)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(isNew ? "shop.edit.title.add" : "shop.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew { Button("button.cancel") { dismiss() } }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("button.save") { save() }.disabled(!isValid)
            }
        }
        .onAppear { loadFields() }
    }

    private func loadFields() {
        guard let shop else { return }
        zName = shop.zName
        zNote = shop.zNote
    }

    private func save() {
        let name = zName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let shop {
            shop.zName    = name
            shop.zNote    = zNote
            shop.sortName = name
        } else {
            let s = E4shop(zName: name, zNote: zNote, sortName: name)
            context.insert(s)
        }
        dismiss()
    }
}
