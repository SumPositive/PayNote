import SwiftUI
import SwiftData

struct BankEditView: View {
    var bank: E8bank?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \E8bank.nRow)   private var allBanks: [E8bank]

    @State private var zName = ""
    @State private var zNote = ""

    private var isNew:   Bool { bank == nil }
    private var isValid: Bool { !zName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("bank.field.name", text: $zName)
                    .autocorrectionDisabled()
            }
            Section {
                TextField("label.note", text: $zNote)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(isNew ? "bank.edit.title.add" : "bank.edit.title.edit")
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
        guard let bank else { return }
        zName = bank.zName
        zNote = bank.zNote
    }

    private func save() {
        let name = zName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let bank {
            bank.zName = name
            bank.zNote = zNote
        } else {
            let row = Int32((allBanks.map { Int($0.nRow) }.max() ?? -1) + 1)
            context.insert(E8bank(zName: name, zNote: zNote, nRow: row))
        }
        dismiss()
    }
}
