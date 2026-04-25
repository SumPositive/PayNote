import SwiftUI
import SwiftData

struct TopMenuView: View {
    @Binding var selectedDestination: AppDestination?
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner

    @Query(filter: #Predicate<E7payment> { !$0.isPaid },
           sort: \E7payment.date, order: .reverse)
    private var unpaidPayments: [E7payment]

    private var totalUnpaid: Decimal {
        // メニューの未払計は支払状態の元データ（E7payment）から直接算出する
        unpaidPayments.reduce(.zero) { $0 + $1.sumAmount }
    }

    var body: some View {
        List(selection: $selectedDestination) {
            // 明細
            Section {
                row(.addRecord,    icon: "plus.circle.fill",  color: .blue,   key: "top.addRecord")
                row(.recordList,   icon: "list.bullet",        color: .indigo, key: "top.recordList")
            }

            // 集計
            Section {
                NavigationLink(value: AppDestination.paymentList) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 8) {
                            // 上段はタイトルと「未払計」を分け、金額を右寄せで強調する
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("top.paymentList")
                                Spacer(minLength: 8)
                                // 「未払計 + 金額」は1行で表示する
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(unpaidTotalLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(totalUnpaid.currencyString())
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(COLOR_UNPAID)
                                }
                            }

                            // 初心者モードではセル内に操作説明を表示する
                            if userLevel == .beginner {
                                paymentGuideText
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .tag(AppDestination.paymentList)
            }

            // マスタ
            Section {
                row(.cardList,     icon: "creditcard",         color: .green,  key: "top.cardList")
                row(.bankList,     icon: "building.columns",   color: .teal,   key: "top.bankList")
                row(.categoryList, icon: "tag",                color: .pink,   key: "top.categoryList")
            }

            // アプリ
            Section {
                row(.settings, icon: "gearshape", color: .gray, key: "top.settings")
            }
        }
        // 先頭セクション前の余白を詰めて、ヘッダ直下をコンパクトにする
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("app.name")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func row(
        _ dest: AppDestination,
        icon: String, color: Color,
        key: LocalizedStringKey
    ) -> some View {
        NavigationLink(value: dest) {
            Label {
                Text(key)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
        .tag(dest)
    }

    /// 「未払計」ラベル（ja/en）
    private var unpaidTotalLabel: String {
        if Locale.current.language.languageCode?.identifier == "ja" {
            return "未払計"
        }
        return "Unpaid Total"
    }

    /// 初心者向けガイド文（セル内表示）
    @ViewBuilder
    private var paymentGuideText: some View {
        if Locale.current.language.languageCode?.identifier == "ja" {
            VStack(alignment: .leading, spacing: 2) {
                Text("適時、引き落とし状況を見てください。")
                Text("口座からの引き落としが確認できれば、")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(COLOR_UNPAID)
                    Text("をタップしてください。")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("済みへ移動します。いつでも未払に戻すことも可能です。")
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check Schedule as needed.")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("When debit is confirmed, tap")
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(COLOR_UNPAID)
                    Text("to move it to Paid.")
                }
                Text("You can always move it back to Unpaid.")
            }
        }
    }
}
