import SwiftUI
import SwiftData

struct CardEditView: View {
    var card: E1card?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \E1card.nRow)   private var allCards: [E1card]
    @Query(sort: \E8bank.nRow)   private var banks: [E8bank]

    // Basic
    @State private var zName    = ""
    @State private var zNote    = ""
    @State private var isDebit  = false
    @State private var selectedBank: E8bank?

    // Credit card dates
    @State private var closingDay: Int16 = 20
    @State private var payDay:     Int16 = 27
    @State private var payMonth:   Int16 = 1

    // Bonus months (0=none, 1-12)
    @State private var bonus1: Int16 = 0
    @State private var bonus2: Int16 = 0

    private var isNew:   Bool { card == nil }
    private var isValid: Bool { !zName.trimmingCharacters(in: .whitespaces).isEmpty }

    // Closing day picker options: 0(debit), 1-28, 29(末日)
    private let closingDayOptions: [Int16] = [0] + Array(1...28) + [29]
    // Pay day options: 1-28, 29(末日)
    private let payDayOptions:    [Int16] = Array(1...28) + [29]
    private let payMonthOptions:  [Int16] = [0, 1, 2]
    private let bonusMonthOptions:[Int16] = Array(0...12)

    var body: some View {
        Form {
            // 基本情報
            Section {
                TextField("card.field.name", text: $zName)
                    .autocorrectionDisabled()
                Picker("card.field.bank", selection: $selectedBank) {
                    Text("label.noSelection").tag(Optional<E8bank>(nil))
                    ForEach(banks) { b in
                        Text(b.zName).tag(Optional(b))
                    }
                }
            }

            // デビット切替
            Section {
                Toggle("card.closingDay.debit", isOn: $isDebit)
            }

            // クレジット設定
            if !isDebit {
                Section("card.field.closingDay") {
                    Picker("card.field.closingDay", selection: $closingDay) {
                        ForEach(Array(1...28), id: \.self) { d in
                            Text("\(d)").tag(Int16(d))
                        }
                        Text("card.closingDay.end").tag(Int16(29))
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section("card.field.payDay") {
                    Picker("card.field.payDay", selection: $payDay) {
                        ForEach(Array(1...28), id: \.self) { d in
                            Text("\(d)").tag(Int16(d))
                        }
                        Text("card.closingDay.end").tag(Int16(29))
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section("card.field.payMonth") {
                    Picker("card.field.payMonth", selection: $payMonth) {
                        Text("card.payMonth.current").tag(Int16(0))
                        Text("card.payMonth.next").tag(Int16(1))
                        Text("card.payMonth.twoMonths").tag(Int16(2))
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("card.field.bonus1") {
                    Picker("card.field.bonus1", selection: $bonus1) {
                        Text("card.bonus.none").tag(Int16(0))
                        ForEach(Array(1...12), id: \.self) { m in
                            Text(monthName(m)).tag(Int16(m))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section("card.field.bonus2") {
                    Picker("card.field.bonus2", selection: $bonus2) {
                        Text("card.bonus.none").tag(Int16(0))
                        ForEach(Array(1...12), id: \.self) { m in
                            Text(monthName(m)).tag(Int16(m))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
            }

            // メモ
            Section {
                TextField("card.field.note", text: $zNote, axis: .vertical)
                    .lineLimit(3...)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(isNew ? "card.edit.title.add" : "card.edit.title.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isNew { Button("button.cancel") { dismiss() } }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("button.save") { save() }.disabled(!isValid)
            }
        }
        .onAppear { loadFields() }
        .onChange(of: isDebit) { _, newVal in
            if newVal { closingDay = 0 } else if closingDay == 0 { closingDay = 20 }
        }
    }

    // MARK: - Helpers

    private func monthName(_ m: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        return fmt.monthSymbols[m - 1]
    }

    private func loadFields() {
        guard let card else { return }
        zName       = card.zName
        zNote       = card.zNote
        isDebit     = card.isDebit
        closingDay  = card.isDebit ? 20 : card.nClosingDay
        payDay      = card.nPayDay
        payMonth    = card.nPayMonth
        bonus1      = card.nBonus1
        bonus2      = card.nBonus2
        selectedBank = card.e8bank
    }

    private func save() {
        let name = zName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let closing: Int16 = isDebit ? 0 : closingDay
        let pay: Int16     = isDebit ? 0 : payDay
        let month: Int16   = isDebit ? 0 : payMonth
        let b1: Int16      = isDebit ? 0 : bonus1
        let b2: Int16      = isDebit ? 0 : bonus2

        if let card {
            card.zName        = name
            card.zNote        = zNote
            card.nClosingDay  = closing
            card.nPayDay      = pay
            card.nPayMonth    = month
            card.nBonus1      = b1
            card.nBonus2      = b2
            card.e8bank       = selectedBank
            card.dateUpdate   = Date()
        } else {
            let row = Int32((allCards.map { Int($0.nRow) }.max() ?? -1) + 1)
            let c = E1card(
                zName: name, zNote: zNote, nRow: row,
                nClosingDay: closing, nPayDay: pay, nPayMonth: month,
                nBonus1: b1, nBonus2: b2, dateUpdate: Date()
            )
            c.e8bank = selectedBank
            context.insert(c)
        }
        dismiss()
    }
}
