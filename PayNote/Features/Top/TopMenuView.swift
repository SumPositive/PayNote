import SwiftUI
import SwiftData

struct TopMenuView: View {
    @Binding var selectedDestination: AppDestination?

    @Query(filter: #Predicate<E1card> { _ in true },
           sort: \E1card.nRow)
    private var cards: [E1card]

    private var totalUnpaid: Decimal {
        cards.reduce(.zero) { $0 + $1.sumUnpaid }
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("top.paymentList")
                            if totalUnpaid != .zero {
                                Text(totalUnpaid.currencyString())
                                    .font(.caption)
                                    .foregroundStyle(COLOR_UNPAID)
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
}
