import SwiftUI

/// 3段組みの日付表示（年・月日・曜日）
/// 履歴・引き落とし状況・カード別一覧などで共通利用する。
struct StackedDateView: View {
    let date: Date

    /// 年は控えめに、曜日は視認性優先で一段大きく
    private static let yearFont:    Font = .caption2   // 約11pt
    private static let weekdayFont: Font = .caption    // 約12pt

    var body: some View {
        VStack(spacing: 0) {
            Text(AppDateFormat.yearText(date))
                .font(Self.yearFont)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
            Text(AppDateFormat.monthDayText(date))
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            Text(AppDateFormat.weekdayText(date))
                .font(Self.weekdayFont)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: true, vertical: false)
    }
}
