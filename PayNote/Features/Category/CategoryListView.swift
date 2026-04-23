import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Query private var categories: [E5category]
    @Environment(\.modelContext) private var context

    @AppStorage(AppStorageKey.categorySortMode) private var sortModeRaw: Int = SortMode.recent.rawValue

    @State private var showAddSheet    = false
    @State private var deleteTarget: E5category?
    @State private var showDeleteAlert = false

    private var sortMode: SortMode { SortMode(rawValue: sortModeRaw) ?? .recent }

    private var sorted: [E5category] {
        switch sortMode {
        case .recent: categories.sorted { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }
        case .count:  categories.sorted { $0.sortCount > $1.sortCount }
        case .amount: categories.sorted { $0.sortAmount > $1.sortAmount }
        case .name:   categories.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            ForEach(sorted) { cat in
                NavigationLink {
                    CategoryEditView(category: cat)
                } label: {
                    CategoryRow(cat: cat, sortMode: sortMode)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget    = cat
                        showDeleteAlert = true
                    } label: {
                        Label("button.delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("category.list.title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Picker("shop.field.sortMode", selection: $sortModeRaw) {
                        ForEach(SortMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.localizedKey)).tag(mode.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack { CategoryEditView(category: nil) }
        }
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                if let c = deleteTarget { context.delete(c) }
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.message")
        }
    }
}

private struct CategoryRow: View {
    let cat: E5category
    let sortMode: SortMode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.zName)
                if !cat.zNote.isEmpty {
                    Text(cat.zNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch sortMode {
            case .recent:
                if let d = cat.sortDate {
                    Text(d.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .count:
                Text("\(cat.sortCount)")
                    .font(.caption).foregroundStyle(.secondary)
            case .amount:
                Text(cat.sortAmount.currencyString())
                    .font(.caption).foregroundStyle(.secondary)
            case .name:
                EmptyView()
            }
        }
    }
}
