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
                row(
                    .addRecord,
                    icon: "plus.circle.fill",
                    color: .blue,
                    key: "top.addRecord",
                    beginnerHelp: "top.help.addRecord"
                )
                row(
                    .recordList,
                    icon: "list.bullet",
                    color: .indigo,
                    key: "top.recordList",
                    beginnerHelp: "top.help.recordList"
                )
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
                                    Text("top.paymentList.unpaidTotal")
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
                row(
                    .cardList,
                    icon: "creditcard",
                    color: .green,
                    key: "top.cardList",
                    beginnerHelp: "top.help.cardList"
                )
                row(
                    .bankList,
                    icon: "building.columns",
                    color: .teal,
                    key: "top.bankList",
                    beginnerHelp: "top.help.bankList"
                )
                row(
                    .categoryList,
                    icon: "tag",
                    color: .pink,
                    key: "top.categoryList",
                    beginnerHelp: "top.help.categoryList"
                )
            }

            // アプリ
            Section {
                row(
                    .settings,
                    icon: "gearshape",
                    color: .gray,
                    key: "top.settings",
                    beginnerHelp: "top.help.settings"
                )
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
        key: LocalizedStringKey,
        beginnerHelp: LocalizedStringKey? = nil
    ) -> some View {
        NavigationLink(value: dest) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(key)
                    if userLevel == .beginner, let beginnerHelp {
                        Text(beginnerHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tag(dest)
    }

    /// 初心者向けガイド文（セル内表示）
    private var paymentGuideText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("top.help.paymentList.line1")
            Text("top.help.paymentList.line2")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(COLOR_UNPAID)
                Text("top.help.paymentList.line3")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("top.help.paymentList.line4")
        }
    }
}
