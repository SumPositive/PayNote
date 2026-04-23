import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.enableInstallment) private var enableInstallment = false
    @AppStorage(AppStorageKey.roundBankers)      private var roundBankers      = false
    @AppStorage(AppStorageKey.appearanceMode)    private var appearanceMode: AppearanceMode = .automatic

    var body: some View {
        Text("settings.stub")
            .navigationTitle("top.settings")
            .navigationBarTitleDisplayMode(.large)
    }
}
