import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppStorageKey.userLevel)         private var userLevel: UserLevel = .beginner
    @AppStorage(AppStorageKey.appearanceMode)    private var appearanceMode: AppearanceMode = .automatic
    @AppStorage(AppStorageKey.fontScale)         private var fontScale: FontScale = .standard
    @AppStorage(AppStorageKey.afterSaveAction)   private var afterSaveAction: AfterSaveAction = .goBack
    @AppStorage(AppStorageKey.openAddOnActive)   private var openAddOnActive = false
    @AppStorage(AppStorageKey.paymentWindowDays) private var paymentWindowDays = 7

    @Environment(\.modelContext) private var context

    @State private var showShareSheet  = false
    @State private var showImportPicker = false
    @State private var exportedURL: URL?
    @State private var showAboutSheet  = false
    @State private var showPruneOldRecordsConfirm = false
    @State private var alertItem: SettingsAlertItem?
    @State private var isWorking = false
    @State private var progressMessage = ""
    @State private var progressHint = ""

    var body: some View {
        List {
            Section("settings.panel.display") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("settings.userLevel")
                            .font(.subheadline)
                        Picker("settings.userLevel", selection: $userLevel) {
                            ForEach(UserLevel.allCases) { level in
                                Text(LocalizedStringKey(level.localizedKey)).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if userLevel == .beginner {
                        Text("settings.help.userLevel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Text("settings.appearance")
                        .font(.subheadline)
                    Picker("settings.appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.localizedKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("settings.fontScale")
                            .font(.subheadline)
                        Picker("settings.fontScale", selection: $fontScale) {
                            ForEach(FontScale.allCases) { scale in
                                Text(LocalizedStringKey(scale.localizedKey)).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if userLevel == .beginner {
                        Text("settings.help.fontScale")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("settings.panel.payment") {
                Toggle("settings.openAddOnActive", isOn: $openAddOnActive)

                HStack(spacing: 8) {
                    Text("settings.afterSave")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker("settings.afterSave", selection: $afterSaveAction) {
                        ForEach(AfterSaveAction.allCases) { action in
                            Text(LocalizedStringKey(action.localizedKey)).tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .tint(.accentColor)
                }

                HStack(spacing: 8) {
                    Text("settings.paymentWindow")
                        .font(.subheadline)
                        // 見出しはできるだけ1行を優先する
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                    Picker("settings.paymentWindow", selection: $paymentWindowDays) {
                        ForEach(Array(1...20), id: \.self) { day in
                            Text(windowLabel(day)).tag(day)
                        }
                        Text(windowLabel(30)).tag(30)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    // 選択値は必要幅だけ使い、見出しを圧迫しない
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .tint(.accentColor)
                }
            }

            Section("settings.panel.share") {
                Button {
                    exportJSON()
                } label: {
                    Label("settings.jsonExport.all", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking)

                Button {
                    showImportPicker = true
                } label: {
                    Label(importButtonText, systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)

                Button {
                    showPruneOldRecordsConfirm = true
                } label: {
                    Label(pruneOldRecordsButtonText, systemImage: "trash")
                }
                .disabled(isWorking)
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
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importJSON(from: url)
            case .failure(let error):
                alertItem = .raw(title: errorTitleText, message: error.localizedDescription)
            }
        }
        .alert(item: $alertItem) { item in
            let title: Text = {
                if let titleKey = item.titleKey {
                    return Text(LocalizedStringKey(titleKey))
                }
                return Text(item.rawTitle ?? errorTitleText)
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
        .alert(pruneOldRecordsConfirmTitle, isPresented: $showPruneOldRecordsConfirm) {
            Button(pruneOldRecordsConfirmDeleteText, role: .destructive) {
                pruneOldRecords()
            }
            Button("button.cancel", role: .cancel) {}
        } message: {
            Text(pruneOldRecordsConfirmMessage)
        }
        .overlay {
            if isWorking {
                ZStack {
                    // 入出力処理中は背面操作を受け付けない
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)
                        Text(progressMessage)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(progressHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    /// 設定画面のアラート表示モデル
    private struct SettingsAlertItem: Identifiable {
        let id: String
        let titleKey: String?
        let messageKey: String?
        let rawTitle: String?
        let rawMessage: String?

        /// ローカライズキーを使うアラート
        static func localized(id: String, titleKey: String, messageKey: String) -> SettingsAlertItem {
            SettingsAlertItem(
                id: id,
                titleKey: titleKey,
                messageKey: messageKey,
                rawTitle: nil,
                rawMessage: nil
            )
        }

        /// 任意文字列を使うアラート
        static func raw(title: String, message: String) -> SettingsAlertItem {
            SettingsAlertItem(
                id: "\(title):\(message)",
                titleKey: nil,
                messageKey: nil,
                rawTitle: title,
                rawMessage: message
            )
        }
    }

    private func exportJSON() {
        Task { @MainActor in
            isWorking = true
            progressMessage = exportPreparingText
            progressHint = exportHintText
            // オーバーレイ描画を先に反映する
            await Task.yield()
            defer { isWorking = false }

            do {
                let data = try await JSONExport.exportData(context: context) { phase in
                    // 工程の説明文を逐次切り替える
                    progressMessage = phase.message(locale: Locale.current)
                }
                let fmt  = DateFormatter()
                fmt.dateFormat = "yyyyMMdd_HHmmss"
                let name = "CreditMemo_\(fmt.string(from: Date())).json"
                let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                progressMessage = exportWritingText
                await Task.yield()
                try data.write(to: url)
                exportedURL    = url
                showShareSheet = true
            } catch {
                alertItem = .raw(title: errorTitleText, message: error.localizedDescription)
            }
        }
    }

    private func importJSON(from url: URL) {
        Task { @MainActor in
            isWorking = true
            progressHint = importHintText
            progressMessage = importPreparingText
            await Task.yield()
            defer { isWorking = false }

            let startedAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let result = try await JSONImport.importData(from: url, context: context) { phase in
                    // 工程の説明文を逐次切り替える
                    progressMessage = phase.message(locale: Locale.current)
                }
                alertItem = .raw(title: importDoneTitleText, message: importDoneMessage(result))
            } catch {
                alertItem = .raw(title: errorTitleText, message: error.localizedDescription)
            }
        }
    }

    /// エクスポート開始時の説明文
    private var exportPreparingText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "エクスポート準備中…"
        }
        return "Preparing export..."
    }

    /// ファイル書き込み時の説明文
    private var exportWritingText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "ファイルへ書き込み中…"
        }
        return "Writing file..."
    }

    /// エクスポート中の補足説明
    private var exportHintText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "データ量により数秒かかることがあります"
        }
        return "This may take a few seconds depending on data volume."
    }

    /// インポートボタン文言
    private var importButtonText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "データをインポートする"
        }
        return "Import Data"
    }

    /// インポート開始時の説明文
    private var importPreparingText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "インポート準備中…"
        }
        return "Preparing import..."
    }

    /// インポート中の補足説明
    private var importHintText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "不足している配列キーは無視し、含まれるデータだけを取り込みます"
        }
        return "Missing sections are ignored. Only included data will be imported."
    }

    /// 3年超履歴削除ボタン文言
    private var pruneOldRecordsButtonText: String {
        NSLocalizedString("retention.settings.button", comment: "")
    }

    /// 3年超履歴削除確認タイトル
    private var pruneOldRecordsConfirmTitle: String {
        NSLocalizedString("retention.prompt.title", comment: "")
    }

    /// 3年超履歴削除確認文
    private var pruneOldRecordsConfirmMessage: String {
        NSLocalizedString("retention.prompt.message", comment: "")
    }

    /// 3年超履歴削除実行ボタン文言
    private var pruneOldRecordsConfirmDeleteText: String {
        NSLocalizedString("retention.prompt.delete", comment: "")
    }

    /// 共通エラータイトル
    private var errorTitleText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "エラー"
        }
        return "Error"
    }

    /// インポート完了タイトル
    private var importDoneTitleText: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "インポート完了"
        }
        return "Import Complete"
    }

    /// インポート完了メッセージ
    private func importDoneMessage(_ result: JSONImport.Result) -> String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return """
            口座 \(result.bankCount) 件
            決済手段 \(result.cardCount) 件
            利用店 \(result.shopCount) 件
            タグ \(result.categoryCount) 件
            決済履歴 \(result.recordCount) 件
            請求状態反映 \(result.invoiceStateCount) 件
            支払状態反映 \(result.paymentStateCount) 件
            """
        }
        return """
        Accounts: \(result.bankCount)
        Payment Methods: \(result.cardCount)
        Shops: \(result.shopCount)
        Tags: \(result.categoryCount)
        Records: \(result.recordCount)
        Invoice States: \(result.invoiceStateCount)
        Payment States: \(result.paymentStateCount)
        """
    }

    /// 3年超履歴削除を実行する
    private func pruneOldRecords() {
        Task { @MainActor in
            isWorking = true
            // 実行中の状態が伝わるように進行文言を更新する
            progressMessage = pruneOldRecordsProgressText
            progressHint = pruneOldRecordsProgressHintText
            await Task.yield()
            defer { isWorking = false }

            do {
                try RecordService.deleteRecords(olderThanYears: 3, context: context)
                alertItem = .raw(title: pruneOldRecordsDoneTitle, message: pruneOldRecordsDoneMessage)
            } catch {
                alertItem = .raw(title: errorTitleText, message: error.localizedDescription)
            }
        }
    }

    /// 3年超履歴削除中の進行文言
    private var pruneOldRecordsProgressText: String {
        NSLocalizedString("retention.progress.cleaning", comment: "")
    }

    /// 3年超履歴削除中の補足文
    private var pruneOldRecordsProgressHintText: String {
        NSLocalizedString("retention.progress.hint", comment: "")
    }

    /// 3年超履歴削除完了タイトル
    private var pruneOldRecordsDoneTitle: String {
        NSLocalizedString("retention.result.doneTitle", comment: "")
    }

    /// 3年超履歴削除完了文
    private var pruneOldRecordsDoneMessage: String {
        NSLocalizedString("retention.result.done", comment: "")
    }
}

private extension SettingsView {
    /// 集計期間ラベル
    func windowLabel(_ days: Int) -> String {
        let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
        if days == 30 {
            return isJapanese ? "1ヶ月" : "1 Month"
        }
        return isJapanese ? "\(days)日" : "\(days) Days"
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
