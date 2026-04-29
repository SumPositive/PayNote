import SwiftUI
import SwiftData

/// アプリのナビゲーションルート
/// - 標準/大:    iPhone は NavigationSplitView が自動縮退、iPad はサイドバー付き
/// - 特大:       スプリットなし NavigationStack（横向き専用）
struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppStorageKey.openAddOnActive) private var openAddOnActive = false
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .standard
    @AppStorage(AppStorageKey.retentionPromptCompleted) private var retentionPromptCompleted = false
    @State private var selectedDestination: AppDestination?
    @State private var addRecordRefreshID = UUID()
    @State private var showRetentionPrompt = false
    @State private var retentionResultMessage = ""
    @State private var showRetentionResult = false
    @ScaledMetric(relativeTo: .title) private var emptyIconSize: CGFloat = 64
    /// 特大モード用スタックパス
    @State private var stackPath: [AppDestination] = []
    
    private var shouldUseStackBody: Bool {
        // iPad は常にスプリット表示を優先する
        if UIDevice.current.userInterfaceIdiom == .pad {
            return false
        }
        // 手動で「特大」を選んだ場合は従来通りスタック表示
        if fontScale == .xLarge {
            return true
        }
        // 自動時は「大以上」でスタック表示へ切り替える（iPhoneのみ）
        if fontScale.followsSystem && shouldUseStackForSystemFontSize {
            return true
        }
        return false
    }
    private var shouldUseStackForSystemFontSize: Bool {
        switch dynamicTypeSize {
        case .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }

    var body: some View {
        if shouldUseStackBody {
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
        .task { await runInitialMaintenanceIfNeeded() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, openAddOnActive else { return }
            addRecordRefreshID = UUID()
            stackPath = [.addRecord]
        }
        .alert(retentionPromptTitle, isPresented: $showRetentionPrompt) {
            Button(retentionPromptDeleteButton, role: .destructive) {
                Task { @MainActor in
                    let ok = await deleteOldRecordsWithPrompt()
                    if ok {
                        retentionPromptCompleted = true
                    }
                }
            }
            Button(retentionPromptKeepButton, role: .cancel) {
                retentionPromptCompleted = true
            }
        } message: {
            Text(retentionPromptMessage)
        }
        .alert(retentionResultTitle, isPresented: $showRetentionResult) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(retentionResultMessage)
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
                            .font(.system(size: emptyIconSize))
                            .foregroundStyle(.secondary)
                        Text("app.selectMenu")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await runInitialMaintenanceIfNeeded() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, openAddOnActive else { return }
            addRecordRefreshID = UUID()
            selectedDestination = .addRecord
        }
        .alert(retentionPromptTitle, isPresented: $showRetentionPrompt) {
            Button(retentionPromptDeleteButton, role: .destructive) {
                Task { @MainActor in
                    let ok = await deleteOldRecordsWithPrompt()
                    if ok {
                        retentionPromptCompleted = true
                    }
                }
            }
            Button(retentionPromptKeepButton, role: .cancel) {
                retentionPromptCompleted = true
            }
        } message: {
            Text(retentionPromptMessage)
        }
        .alert(retentionResultTitle, isPresented: $showRetentionResult) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(retentionResultMessage)
        }
    }

    /// 起動時の軽量メンテナンスと履歴削除同意の表示を行う
    private func runInitialMaintenanceIfNeeded() async {
        SeedData.seedIfNeeded(context: modelContext)
        // 起動時に請求孤児を掃除して、旧データ不整合のクラッシュを抑える
        RecordService.cleanupOrphanBilling(context: modelContext)
        if modelContext.hasChanges {
            try? modelContext.save()
        }

        if retentionPromptCompleted == false {
            await MainActor.run {
                showRetentionPrompt = true
            }
        }
    }

    private var retentionPromptTitle: String {
        NSLocalizedString("retention.prompt.title", comment: "")
    }

    private var retentionPromptMessage: String {
        NSLocalizedString("retention.prompt.message", comment: "")
    }

    private var retentionPromptDeleteButton: String {
        NSLocalizedString("retention.prompt.delete", comment: "")
    }

    private var retentionPromptKeepButton: String {
        NSLocalizedString("retention.prompt.keep", comment: "")
    }

    /// 初回同意時: 3年超履歴を削除する（事前エキスポートをユーザーへ案内）
    private func deleteOldRecordsWithPrompt() async -> Bool {
        do {
            try RecordService.deleteRecords(olderThanYears: 3, context: modelContext)
            retentionResultMessage = retentionDoneMessage
            showRetentionResult = true
            return true
        } catch {
            retentionResultMessage = error.localizedDescription
            showRetentionResult = true
            return false
        }
    }

    private var retentionResultTitle: String {
        NSLocalizedString("retention.result.title", comment: "")
    }

    private var retentionDoneMessage: String {
        NSLocalizedString("retention.result.done", comment: "")
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
