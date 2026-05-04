import SwiftUI
import SwiftData

struct BankListView: View {
    @Query(sort: \E8bank.nRow) private var banks: [E8bank]
    @Environment(\.modelContext) private var context
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner

    @State private var showAddSheet    = false
    @State private var deleteTarget: E8bank?
    @State private var showDeleteAlert = false

    var body: some View {
        List {
            if userLevel == .beginner {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("bank.beginner.line1")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("bank.beginner.line2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("bank.beginner.line3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            ForEach(banks) { bank in
                NavigationLink {
                    BankEditView(bank: bank)
                } label: {
                    BankRow(bank: bank)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget    = bank
                        showDeleteAlert = true
                    } label: {
                        Label("button.delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: move)
        }
        .scalableNavigationTitle("bank.list.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack { BankEditView(bank: nil) }
        }
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                if let b = deleteTarget {
                    try? BankService.delete(b, context: context)
                }
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.bank.message")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = banks
        list.move(fromOffsets: source, toOffset: destination)
        for (i, b) in list.enumerated() { b.nRow = Int32(i) }
    }
}

private struct BankRow: View {
    let bank: E8bank
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bank.zName)
            if !bank.zNote.isEmpty {
                Text(bank.zNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
