import SwiftUI

// MARK: - テンキーシート

/// 00キー付きテンキー入力シート
struct NumericKeypadSheet: View {
    let title: LocalizedStringKey
    let placeholder: Decimal
    let maxValue: Decimal
    let onCommit: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits: String = ""

    private var isEmpty: Bool { digits.isEmpty }
    private var isCompact: Bool { UIScreen.main.bounds.height <= 700 }
    private var sheetSpacing: CGFloat { isCompact ? 14 : 20 }
    private var displayFontSize: CGFloat { isCompact ? 44 : 52 }
    private var locale: Locale { .current }
    private var fractionDigits: Int { Decimal.currencyFractionDigits(locale: locale) }

    private var committedValue: Decimal {
        guard !isEmpty, let minorUnits = Decimal(string: digits) else { return placeholder }
        return min(Decimal.fromMinorUnits(minorUnits, locale: locale), maxValue)
    }

    /// 入力中の金額表示は、通貨記号の位置も含めてロケールへ合わせる
    private var displayAmountText: String {
        committedValue.currencyString(locale: locale)
    }

    /// 入力可能な最大小数単位の桁数
    private var maxMinorUnitsText: String {
        (maxValue.minorUnits(locale: locale) as NSDecimalNumber).stringValue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: sheetSpacing) {
                // 入力表示
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Spacer()
                    Text(displayAmountText)
                        .font(.system(size: displayFontSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isEmpty ? Color(.tertiaryLabel) : Color(.label))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: digits)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, isCompact ? 4 : 8)

                // テンキー
                NumericKeypad(compact: isCompact) { key in handleKey(key) }

                // 決定ボタン
                Button {
                    onCommit(committedValue)
                    dismiss()
                } label: {
                    Text("button.done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, isCompact ? 6 : 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .presentationDetents(isCompact ? [.fraction(0.7), .large] : [.fraction(0.65), .large])
        .presentationDragIndicator(.visible)
    }

    private func handleKey(_ key: NumericKeypadKey) {
        switch key {
        case .digit(let d):   appendDigits(String(d))
        case .doubleZero:     appendDigits("00")
        case .delete:
            if !digits.isEmpty { digits.removeLast() }
        }
    }

    private func appendDigits(_ suffix: String) {
        let next: String
        if digits.isEmpty || digits == "0" {
            next = suffix.hasPrefix("0") ? "0" : suffix
        } else {
            next = digits + suffix
        }
        guard let minorUnits = Decimal(string: next), 0 <= minorUnits else { return }
        guard next.count <= maxMinorUnitsText.count else { return }
        guard Decimal.fromMinorUnits(minorUnits, locale: locale) <= maxValue else { return }
        digits = next
    }
}

// MARK: - テンキーキー

enum NumericKeypadKey {
    case digit(Int)
    case doubleZero
    case delete
}

// MARK: - テンキーレイアウト

struct NumericKeypad: View {
    let compact: Bool
    let onKey: (NumericKeypadKey) -> Void

    private let rows = [[7, 8, 9], [4, 5, 6], [1, 2, 3]]

    init(compact: Bool = false, onKey: @escaping (NumericKeypadKey) -> Void) {
        self.compact = compact
        self.onKey = onKey
    }

    private var spacing: CGFloat    { compact ? 8 : 10 }
    private var hPadding: CGFloat   { compact ? 16 : 20 }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { digit in
                        KeypadDigitButton(label: "\(digit)", compact: compact) {
                            onKey(.digit(digit))
                        }
                    }
                }
            }
            HStack(spacing: spacing) {
                KeypadDigitButton(label: "0",  compact: compact) { onKey(.digit(0)) }
                KeypadDigitButton(label: "00", compact: compact) { onKey(.doubleZero) }
                KeypadDeleteButton(compact: compact)             { onKey(.delete) }
            }
        }
        .padding(.horizontal, hPadding)
    }
}

// MARK: - ボタンパーツ

private struct KeypadDigitButton: View {
    let label: String
    let compact: Bool
    let action: () -> Void

    private var minHeight: CGFloat { compact ? 52 : 56 }
    private var font: Font { compact ? .title2.weight(.medium) : .title.weight(.medium) }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct KeypadDeleteButton: View {
    let compact: Bool
    let action: () -> Void

    private var minHeight: CGFloat { compact ? 52 : 56 }
    private var font: Font { compact ? .title3 : .title2 }

    var body: some View {
        Button(action: action) {
            Image(systemName: "delete.left")
                .font(font)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
