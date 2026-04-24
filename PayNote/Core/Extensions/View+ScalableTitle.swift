import SwiftUI

extension View {
    /// navigationBarTitleDisplayMode(.large) はスケールしないため、
    /// inline + principal ToolbarItem で可変フォントタイトルを実現する。
    func scalableNavigationTitle(_ key: LocalizedStringKey) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(key)
                        .font(.title3.bold())
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
            }
    }

    /// 日付や名称など、ローカライズキーではない値をそのまま表示する。
    func scalableNavigationTitle(verbatim title: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: title)
                        .font(.title3.bold())
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
            }
    }
}
