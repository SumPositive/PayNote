import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(AppStorageKey.userLevel)         private var userLevel: UserLevel = .beginner
    @AppStorage(AppStorageKey.appearanceMode)    private var appearanceMode: AppearanceMode = .automatic
    @AppStorage(AppStorageKey.afterSaveAction)   private var afterSaveAction: AfterSaveAction = .goBack
    @AppStorage(AppStorageKey.openAddOnActive)   private var openAddOnActive = false

    @Environment(\.modelContext) private var context

    @State private var showShareSheet  = false
    @State private var exportedURL: URL?
    @State private var showAboutSheet  = false
    @State private var alertItem: SettingsAlertItem?

    var body: some View {
        List {
            Section("settings.panel.display") {
                Picker("settings.userLevel", selection: $userLevel) {
                    ForEach(UserLevel.allCases) { level in
                        Text(LocalizedStringKey(level.localizedKey)).tag(level)
                    }
                }

                Picker("settings.appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.localizedKey)).tag(mode)
                    }
                }
            }

            Section("settings.panel.payment") {
                Toggle("settings.openAddOnActive", isOn: $openAddOnActive)

                Picker("settings.afterSave", selection: $afterSaveAction) {
                    ForEach(AfterSaveAction.allCases) { action in
                        Text(LocalizedStringKey(action.localizedKey)).tag(action)
                    }
                }
            }

            Section("settings.panel.share") {
                Button {
                    exportJSON()
                } label: {
                    Label("settings.jsonExport.all", systemImage: "square.and.arrow.up")
                }
            }

            Section("settings.panel.support") {
                Button {
                    showAboutSheet = true
                } label: {
                    Label("settings.about", systemImage: "info.circle")
                }
            }

            Section("settings.panel.cheer") {
                Button("settings.cheer.tip") {
                    alertItem = .localized(
                        id: "cheer.tip",
                        titleKey: "settings.cheer.title",
                        messageKey: "settings.cheer.tip.todo"
                    )
                }
                Button("settings.cheer.ad") {
                    alertItem = .localized(
                        id: "cheer.ad",
                        titleKey: "settings.cheer.title",
                        messageKey: "settings.cheer.ad.todo"
                    )
                }
            }
        }
        .scalableNavigationTitle("top.settings")
        .sheet(isPresented: $showAboutSheet) {
            NavigationStack { AboutView() }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ExportShareSheet(url: url)
                    .ignoresSafeArea()
            }
        }
        .alert(item: $alertItem) { item in
            let title: Text = {
                if let titleKey = item.titleKey {
                    return Text(LocalizedStringKey(titleKey))
                }
                return Text("alert.saveFailed")
            }()

            let message: Text = {
                if let messageKey = item.messageKey {
                    return Text(LocalizedStringKey(messageKey))
                }
                return Text(item.rawMessage ?? "")
            }()

            return Alert(
                title: title,
                message: message,
                dismissButton: .cancel(Text("button.ok"))
            )
        }
    }

    /// 設定画面のアラート表示モデル
    private struct SettingsAlertItem: Identifiable {
        let id: String
        let titleKey: String?
        let messageKey: String?
        let rawMessage: String?

        /// ローカライズキーを使うアラート
        static func localized(id: String, titleKey: String, messageKey: String) -> SettingsAlertItem {
            SettingsAlertItem(
                id: id,
                titleKey: titleKey,
                messageKey: messageKey,
                rawMessage: nil
            )
        }

        /// 例外文字列など、生メッセージを使うアラート
        static func rawError(_ message: String) -> SettingsAlertItem {
            SettingsAlertItem(
                id: "error:\(message)",
                titleKey: nil,
                messageKey: nil,
                rawMessage: message
            )
        }
    }

    private func exportJSON() {
        do {
            let data = try JSONExport.exportData(context: context)
            let fmt  = DateFormatter()
            fmt.dateFormat = "yyyyMMdd_HHmmss"
            let name = "PayNote_\(fmt.string(from: Date())).json"
            let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url)
            exportedURL    = url
            showShareSheet = true
        } catch {
            alertItem = .rawError(error.localizedDescription)
        }
    }
}

// MARK: - UIActivityViewController ラッパー

private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
