import SwiftUI
import SwiftData

/// アプリのナビゲーションルート
/// - 標準/大:    iPhone は NavigationSplitView が自動縮退、iPad はサイドバー付き
/// - 特大:       スプリットなし NavigationStack（横向き専用）
struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.openAddOnActive) private var openAddOnActive = false
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .standard
    @State private var selectedDestination: AppDestination?
    @State private var addRecordRefreshID = UUID()
    /// 特大モード用スタックパス
    @State private var stackPath: [AppDestination] = []

    var body: some View {
        if fontScale == .xLarge {
            xlargeBody
        } else {
            splitBody
        }
    }

    // MARK: - 特大: スプリットなし NavigationStack

    private var xlargeBody: some View {
        // stackPath と selectedDestination を同期させるバインディング
        let xlargeDest = Binding<AppDestination?>(
            get: { stackPath.last },
            set: { newValue in
                if let v = newValue { stackPath = [v] } else { stackPath = [] }
            }
        )
        return NavigationStack(path: $stackPath) {
            TopMenuView(selectedDestination: xlargeDest)
                .navigationDestination(for: AppDestination.self) { dest in
                    AppDestinationView(
                        destination: dest,
                        selectedDestination: xlargeDest,
                        addRecordRefreshID: addRecordRefreshID
                    )
                }
        }
        .task { SeedData.seedIfNeeded(context: modelContext) }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, openAddOnActive else { return }
            addRecordRefreshID = UUID()
            stackPath = [.addRecord]
        }
    }

    // MARK: - 標準/大: NavigationSplitView

    private var splitBody: some View {
        NavigationSplitView {
            TopMenuView(selectedDestination: $selectedDestination)
        } detail: {
            NavigationStack {
                if let dest = selectedDestination {
                    AppDestinationView(
                        destination: dest,
                        selectedDestination: $selectedDestination,
                        addRecordRefreshID: addRecordRefreshID
                    )
                } else {
                    // iPad 初期表示
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        Text("app.selectMenu")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { SeedData.seedIfNeeded(context: modelContext) }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, openAddOnActive else { return }
            addRecordRefreshID = UUID()
            selectedDestination = .addRecord
        }
    }
}

// MARK: - 画面遷移先

enum AppDestination: Hashable, CaseIterable {
    case addRecord
    case recordList
    case paymentList
    case cardList
    case bankList
    case shopList
    case categoryList
    case settings
    case about
}

// MARK: - 遷移先ビュー振り分け

struct AppDestinationView: View {
    let destination: AppDestination
    @Binding var selectedDestination: AppDestination?
    let addRecordRefreshID: UUID

    var body: some View {
        switch destination {
        case .addRecord:
            RecordEditView(mode: .addNew, onSaved: { selectedDestination = .recordList })
                .id(addRecordRefreshID)
        case .recordList:    RecordListView()
        case .paymentList:   PaymentListView()
        case .cardList:      CardListView()
        case .bankList:      BankListView()
        case .shopList:      ShopListView()
        case .categoryList:  CategoryListView()
        case .settings:      SettingsView()
        case .about:         AboutView()
        }
    }
}
