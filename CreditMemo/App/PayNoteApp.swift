import SwiftUI
import SwiftData
import UIKit

@main
struct CreditMemoApp: App {
    private let supportMailAddress = "sumpo@azukid.com"

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .automatic
    @AppStorage(AppStorageKey.fontScale)      private var fontScale: FontScale = .standard

    var sharedModelContainer: ModelContainer?
    private var containerError: Error?
    private let storeURL: URL
    @State private var migrationMessage = ""
    @State private var isMigrating = false
    @State private var didStartMigration = false
    @State private var showMigrationFailure = false
    @State private var legacyStoreURLs: [URL] = []
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var didShareLegacyData = false
    @State private var showThanksAlert = false

    init() {
        let schema = Schema([
            E1card.self, E2invoice.self, E3record.self,
            E4shop.self, E5category.self, E6part.self,
            E7payment.self, E8bank.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        storeURL = config.url
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
            containerError = nil
        } catch {
            sharedModelContainer = nil
            containerError = error
        }

        // 起動直後の描画を優先するため、マイグレーション実行は body 側の task で開始する
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if fontScale.followsSystem {
                    appRootView
                } else {
                    appRootView
                        .dynamicTypeSize(fontScale.dynamicTypeSize)
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .overlay {
                if isMigrating {
                    ZStack {
                        // 処理待ち中は背面操作を受けないように薄い遮蔽を重ねる
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.large)
                            Text(migrationMessage)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                            Text(AppLaunchProgressText.message(locale: Locale.current, key: .migrationHint))
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    }
                    .allowsHitTesting(true)
                }
            }
            .overlay {
                if showMigrationFailure {
                    ZStack {
                        // エラー選択が完了するまで背面操作を止める
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                        VStack(spacing: 14) {
                            if didShareLegacyData {
                                Text("送信ありがとうございました。このまま次のアップデートをお待ちください")
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("旧アプリのデータ読み出しに失敗しました。旧アプリのデータを送って頂ければ調査対応します。送信先: \(supportMailAddress)")
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                                Button {
                                    shareLegacyStore()
                                } label: {
                                    Text("旧データをメールで送る")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                Button(role: .destructive) {
                                    // 旧データを破棄して、次回起動から新規運用へ切り替える
                                    MigratingFromCoreData.discardLegacyStores(legacyStoreURLs)
                                    MigratingFromCoreData.markMigrationCompleted()
                                    showMigrationFailure = false
                                    guard let container = sharedModelContainer else { return }
                                    SeedData.seedIfNeeded(context: container.mainContext)
                                    RecordService.cleanupOrphanBilling(context: container.mainContext)
                                    if container.mainContext.hasChanges {
                                        try? container.mainContext.save()
                                    }
                                } label: {
                                    Text("旧データを破棄して新しく始める")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(20)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    }
                    .allowsHitTesting(true)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityItemsSheet(items: shareItems) { completed in
                    // 共有が実行された時だけ「送信ありがとう」を表示する
                    if completed {
                        didShareLegacyData = true
                        showThanksAlert = true
                    }
                }
            }
            .alert("送信ありがとうございました。このまま次のアップデートをお待ちください", isPresented: $showThanksAlert) {
                Button("OK", role: .cancel) {}
            }
            .task {
                guard didStartMigration == false else { return }
                didStartMigration = true
                guard let container = sharedModelContainer else { return }
                isMigrating = true
                migrationMessage = AppLaunchProgressText.message(locale: Locale.current, key: .migrationPreparing)
                // オーバーレイ描画を先に反映する
                await Task.yield()
                let outcome = await MigratingFromCoreData().migrateIfNeeded(modelContainer: container) { phase in
                    migrationMessage = phase.message(locale: Locale.current)
                }
                switch outcome {
                case .completed:
                    // マイグレーション完了後に初期データ投入と整合性掃除を実行する
                    SeedData.seedIfNeeded(context: container.mainContext)
                    RecordService.cleanupOrphanBilling(context: container.mainContext)
                    if container.mainContext.hasChanges {
                        try? container.mainContext.save()
                    }
                case .failed(let urls):
                    legacyStoreURLs = urls
                    showMigrationFailure = true
                }
                isMigrating = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background,
                  let container = sharedModelContainer else { return }
            let ctx = container.mainContext
            if ctx.hasChanges { try? ctx.save() }
        }
    }

    private func shareLegacyStore() {
        // SQLite本体とwal/shmをまとめて共有する
        var items: [Any] = [
            "CreditMemo migration failed. Please send attached legacy store files to: \(supportMailAddress)"
        ]
        for base in legacyStoreURLs {
            if FileManager.default.fileExists(atPath: base.path) {
                items.append(base)
            }
            for suffix in ["-wal", "-shm"] {
                let related = URL(fileURLWithPath: base.path + suffix)
                if FileManager.default.fileExists(atPath: related.path) {
                    items.append(related)
                }
            }
        }
        shareItems = items
        showShareSheet = true
    }

    private func renameStoreForRecovery() {
        let fm = FileManager.default
        let bakURL = storeURL.appendingPathExtension("bak")
        try? fm.moveItem(at: storeURL, to: bakURL)
        for suffix in ["-shm", "-wal"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            let dst = URL(fileURLWithPath: bakURL.path + suffix)
            try? fm.moveItem(at: src, to: dst)
        }
        exit(0)
    }

    @ViewBuilder
    private var appRootView: some View {
        if let container = sharedModelContainer {
            ContentView()
                .modelContainer(container)
        } else {
            DatabaseErrorView(error: containerError) {
                renameStoreForRecovery()
            }
        }
    }
}

// MARK: - 共有シート

private struct ActivityItemsSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 起動時進行メッセージ

private enum AppLaunchProgressText {
    enum Key {
        case migrationPreparing
        case migrationHint
    }

    static func message(locale: Locale, key: Key) -> String {
        let isJapanese = locale.language.languageCode?.identifier == "ja"
        switch key {
        case .migrationPreparing:
            return isJapanese ? "移行準備中…" : "Preparing migration..."
        case .migrationHint:
            return isJapanese ? "旧データがある場合は安全に移行してから起動します" : "If legacy data exists, the app migrates it safely before launch."
        }
    }
}
