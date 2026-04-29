import SwiftUI
import SwiftData

struct ShopListView: View {
    @Query private var shops: [E4shop]
    @Environment(\.modelContext) private var context

    @AppStorage(AppStorageKey.shopSortMode) private var sortModeRaw: Int = SortMode.recent.rawValue

    @State private var showAddSheet    = false
    @State private var deleteTarget: E4shop?
    @State private var showDeleteAlert = false

    private var sortMode: SortMode { SortMode(rawValue: sortModeRaw) ?? .recent }

    private var sorted: [E4shop] {
        switch sortMode {
        case .recent: shops.sorted { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }
        case .count:  shops.sorted { $0.sortCount > $1.sortCount }
        case .amount: shops.sorted { $0.sortAmount > $1.sortAmount }
        case .name:   shops.sorted { $0.zName.localizedStandardCompare($1.zName) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            ForEach(sorted) { shop in
                NavigationLink {
                    ShopEditView(shop: shop)
                } label: {
                    ShopRow(shop: shop, sortMode: sortMode)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget    = shop
                        showDeleteAlert = true
                    } label: {
                        Label("button.delete", systemImage: "trash")
                    }
                }
            }
        }
        .scalableNavigationTitle("shop.list.title")
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
            NavigationStack { ShopEditView(shop: nil) }
        }
        .alert("alert.deleteConfirm.title", isPresented: $showDeleteAlert) {
            Button("button.delete", role: .destructive) {
                if let s = deleteTarget { context.delete(s) }
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text("alert.deleteConfirm.message")
        }
    }
}

private struct ShopRow: View {
    let shop: E4shop
    let sortMode: SortMode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(shop.zName)
                if !shop.zNote.isEmpty {
                    Text(shop.zNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch sortMode {
            case .recent:
                if let d = shop.sortDate {
                    Text(AppDateFormat.singleLineText(d))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .count:
                Text("\(shop.sortCount)")
                    .font(.caption).foregroundStyle(.secondary)
            case .amount:
                Text(shop.sortAmount.currencyString())
                    .font(.caption).foregroundStyle(.secondary)
            case .name:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
    }
}
