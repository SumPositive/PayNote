import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(AppStorageKey.enableInstallment) private var enableInstallment = false
    @AppStorage(AppStorageKey.roundBankers)      private var roundBankers      = false
    @AppStorage(AppStorageKey.appearanceMode)    private var appearanceMode: AppearanceMode = .automatic

    @Environment(\.modelContext) private var context

    @State private var showShareSheet  = false
    @State private var exportedURL: URL?
    @State private var exportError: String?
    @State private var showErrorAlert  = false

    var body: some View {
        List {
            Section {
                Picker("settings.appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.localizedKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("settings.appearance")
            }

            Section {
                Toggle("settings.roundBankers", isOn: $roundBankers)
            }

            Section {
                Toggle("settings.enableInstallment", isOn: $enableInstallment)
            } footer: {
                Text("settings.enableInstallment.detail")
            }

            Section {
                Button {
                    exportJSON()
                } label: {
                    Label("settings.jsonExport", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("settings.jsonExport.detail")
            }
        }
        .scalableNavigationTitle("top.settings")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ExportShareSheet(url: url)
                    .ignoresSafeArea()
            }
        }
        .alert("alert.saveFailed", isPresented: $showErrorAlert) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
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
            exportError    = error.localizedDescription
            showErrorAlert = true
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
