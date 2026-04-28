import SwiftUI
import SwiftData

struct TopMenuView: View {
    @Binding var selectedDestination: AppDestination?
    @AppStorage(AppStorageKey.userLevel) private var userLevel: UserLevel = .beginner

    @Query(sort: \E7payment.date, order: .reverse)
    private var allPayments: [E7payment]

    private var unpaidPayments: [E7payment] {
        allPayments.filter { !$0.isPaid }
    }

    private var totalUnpaid: Decimal {
        // メニューの未払計は支払状態の元データ（E7payment）から直接算出する
        unpaidPayments.reduce(.zero) { $0 + $1.sumAmount }
    }

    var body: some View {
        List(selection: $selectedDestination) {
            if userLevel == .beginner {
                Section {
                    BeginnerHelpBlock(
                        titleKey: "top.beginner.title",
                        messageKey: "top.beginner.guide"
                    )
                }
            }
            // 明細
            Section {
                row(.addRecord, icon: "plus.circle.fill", color: .blue, key: "top.addRecord")
                row(.recordList, icon: "list.bullet", color: .indigo, key: "top.recordList")
            }

            // 集計
            Section {
                NavigationLink(value: AppDestination.paymentList) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        // タイトルと未払計が1行に収まらない場合は2行目に表示する
                        ViewThatFits(in: .horizontal) {
                            // 1行版: 各テキストを自然幅で固定して収まるか試す
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("top.paymentList")
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 8)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("top.paymentList.unpaidTotal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text(totalUnpaid.currencyString())
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(COLOR_UNPAID)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            // 2行版: 収まらない場合は未払計を2行目に右寄せで表示
                            VStack(alignment: .leading, spacing: 4) {
                                Text("top.paymentList")
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Spacer(minLength: 0)
                                    Text("top.paymentList.unpaidTotal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(totalUnpaid.currencyString())
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(COLOR_UNPAID)
                                }
                            }
                        }
                    }
                }
                .tag(AppDestination.paymentList)
            }

            // 詳細マスタは達人モードで表示する
            if userLevel == .expert {
                Section {
                    row(.cardList, icon: "creditcard", color: .green, key: "top.cardList")
                    row(.bankList, icon: "building.columns", color: .teal, key: "top.bankList")
                    row(.categoryList, icon: "tag", color: .pink, key: "top.categoryList")
                }
            }

            // アプリ
            Section {
                row(
                    .settings,
                    icon: "gearshape",
                    color: .gray,
                    key: "top.settings"
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
        key: LocalizedStringKey
    ) -> some View {
        NavigationLink(value: dest) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(key)
            }
        }
        .tag(dest)
    }
}

private struct BeginnerHelpBlock: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
            Text(messageKey)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
