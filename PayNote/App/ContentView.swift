import SwiftUI
import SwiftData

/// アプリのナビゲーションルート
/// - iPhone:  NavigationSplitView が自動的に NavigationStack に縮退
/// - iPad:    サイドバー(TopMenuView) ＋ 詳細エリア
struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.openAddOnActive) private var openAddOnActive = false
    @State private var selectedDestination: AppDestination?
    @State private var addRecordRefreshID = UUID()

    var body: some View {
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
            // フォアグラウンド復帰時は新しい決済を開き、日付を最新化するため再生成する
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
