import SwiftUI

/// A labeled slider with a number field beside it, for exact values.
struct SliderField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let decimals: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range)
                TextField(title, value: $value, format: .number.precision(.fractionLength(decimals)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: Design.numberFieldWidth)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: value, clamp)
    }

    private func clamp() {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }
}
