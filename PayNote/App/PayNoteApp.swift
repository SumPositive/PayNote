import SwiftUI
import SwiftData

@main
struct PayNoteApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .automatic

    var sharedModelContainer: ModelContainer?
    private var containerError: Error?
    private let storeURL: URL

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

        if let container = sharedModelContainer {
            MigratingFromCoreData().migrateIfNeeded(modelContainer: container)
        }
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
