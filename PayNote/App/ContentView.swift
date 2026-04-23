import SwiftUI
import SwiftData

/// アプリのナビゲーションルート
/// - iPhone:  NavigationSplitView が自動的に NavigationStack に縮退
/// - iPad:    サイドバー(TopMenuView) ＋ 詳細エリア
struct ContentView: View {

    @State private var selectedDestination: AppDestination? = .recordList

    var body: some View {
        NavigationSplitView {
            TopMenuView(selectedDestination: $selectedDestination)
        } detail: {
            NavigationStack {
                if let dest = selectedDestination {
                    AppDestinationView(destination: dest)
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

    var body: some View {
        switch destination {
        case .addRecord:     RecordEditView(mode: .addNew)
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
