import SwiftUI
import SwiftData

@main
struct PayNoteApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .automatic
    @AppStorage(AppStorageKey.fontScale)      private var fontScale: FontScale = .standard

    var sharedModelContainer: ModelContainer?
    private var containerError: Error?
    private let storeURL: URL
    @State private var migrationMessage = ""
    @State private var isMigrating = false
    @State private var didStartMigration = false

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
                if let container = sharedModelContainer {
                    ContentView()
                        .modelContainer(container)
                } else {
                    DatabaseErrorView(error: containerError) {
                        renameStoreForRecovery()
                    }
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .dynamicTypeSize(fontScale.dynamicTypeSize)
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
            .task {
                guard didStartMigration == false else { return }
                didStartMigration = true
                guard let container = sharedModelContainer else { return }
                isMigrating = true
                migrationMessage = AppLaunchProgressText.message(locale: Locale.current, key: .migrationPreparing)
                // オーバーレイ描画を先に反映する
                await Task.yield()
                await MigratingFromCoreData().migrateIfNeeded(modelContainer: container) { phase in
                    migrationMessage = phase.message(locale: Locale.current)
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
